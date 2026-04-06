= Report of the elevator task - Georg Kiviväli
This report will give an overview of the main design and decisions made. It will also contain the requirements traceability matrix and visualizations of each automaton.

NB! LLM help was used in some paragraphs to help with language

== Design overview

This model consists of 5 main UPPAAL automatons:
+ *ElevatorManager* - Handles main elevator lifecycle
+ *FloorPanel* - The panel which is located on each floor with UP and DOWN buttons
+ *ElevatorPanel* - The panel inside elevator with buttons for different floors
+ *DoorMotorController* - Main controller for doors

*User* automaton interacts with the system to simulate passenger behavior.

*OverloadSensor*, *MotionSensor* and *MaintenanceSwitch* are there to non-deterministically simulate physical world interference such as excess weight, doorway obstruction, and manual mechanic overrides.

There are also several data structure based components:

*Global*
+ `bool elevatorButtons[num_floors]` - Which buttons in the elevator are pressed (true for pressed)
+ `bool floorDoors[num_floors]` - Tracks if the door is open at each floor
+ `FloorButton floorButtons[num_floors]` - Array of structs holding two booleans: up/down. Represents both the physical button press and the visual LED glow.
+ `DisplayData displayData` - Shared data structure which shows global data of where the elevator currently is and its direction.
+ `int current_floor` / `int targetFloor` - Holds where the elevator currently is and where it needs to go.

*ElevatorManager*
+ `int queue[MAX_QUEUE]` - Keeps in memory the requests sent to the elevator.

== Components

=== ElevatorManager
This automaton controls the main elevator lifecycle. It consists of four states: `noOperations`, `inService`, `floorStop`, and `inMaintenance`.

The manager starts at `noOperations`. It listens to `floorCallChannel[id]` and `goToFloorChannel` to change states, which are sent by the Floor and Elevator panels respectively.

To ensure passenger comfort and optimize travel time, the ElevatorManager does not simply serve requests First-In-First-Out (FIFO). Instead, the `processQueue()` function implements a directional sweep optimization (SCAN scheduling algorithm). 

If the elevator is going UP to floor 3 and a user presses the UP button on floor 2, serving floor 2 on the way prevents unnecessary back-and-forth travel. 
To prevent the model from dropping requests or deadlocking when multiple users press buttons simultaneously, the manager utilizes self-loop transitions in both `inService` and `floorStop` states. This ensures the manager remains continuously receptive to new calls regardless of its current lifecycle state.

#figure(
  image("./imgs/elevator_manager.png", width: 80%),
  caption: [ElevatorManager Automaton]
)

=== FloorPanel
The `FloorPanel` is instantiated four times (one for each floor) and handles external passenger requests. 
It utilizes a three-state machine: `Idle`, `ButtonPressed`, and `BothPressed`. It relies on the `floorButtons` array to implicitly represent both the physical button state and the visual LED feedback.

This multi-state design explicitly models complex user behavior, particularly when passengers waiting at the same floor want to go in opposite directions. To handle this fairly, the automaton introduces a local `sentUp` boolean toggle. If both the UP and DOWN buttons are pressed (`BothPressed`), the panel does not clear both requests at once when the elevator arrives. Instead, it clears only the direction that was serviced, toggles `sentUp`, and keeps the other request active. This guarantees alternating service and prevents starvation.

#figure(
  image("./imgs/floor_panel.png", width: 60%),
  caption: [FloorPanel Automaton]
)

=== ElevatorPanel
The `ElevatorPanel` is inside the carriage and manages internal floor selections. 

When a floor is selected, the panel immediately sends a synchronization signal over `doorCloseChannel` to the `DoorMotorController`. This simulates the real-world behavior where pressing an internal floor button actively encourages the doors to begin their closing sequence. The panel then waits in the `Ready` state until the `elevatorArrivedChannel` broadcast is received to prevent button-spamming inside the cabin.

#figure(
  image("./imgs/elevator_panel.png", width: 60%),
  caption: [ElevatorPanel Automaton]
)

=== DoorMotorController
The `DoorMotorController` governs the physical opening and closing of the elevator doors using both time (`doorTimer`) signals.

The manager only dictates *when* the elevator arrives at a floor, but the door controller independently enforces physical safety limits. 
It automatically attempts to close the door after `DOOR_TIMEOUT`. However, the transitions to close the door are strictly guarded by `!motion_detected` and `!overloaded`. By embedding these constraints at the hardware level, it becomes physically impossible for the doors to close if the doorway is obstructed or the cabin is too heavy. 

#figure(
  image("./imgs/door_motor_controller.png", width: 70%),
  caption: [DoorMotorController Automaton]
)

== Requirements Traceability Matrix
\
#table(
  columns: (auto, 1fr, 1.5fr, auto),
  align: (center, left, left, center),
  fill: (col, row) => if row == 0 { luma(220) } else { white },
  
  [*Req ID*], [*Description*], [*Implementation Logic*], [*Query ID*],
  
  [1], [Elevator Manager States], [Implemented as 4 locations in `ElevatorManager`: `noOperations`, `inService`, `floorStop`, `inMaintenance`.], [R4, M-Reach],
  [2 & 5], [LED Indicators Display], [Implicitly tracked via `floorButtons[id].up/down` and `elevatorButtons`. Turning true represents the LED glowing.], [-],
  [3 & 4], [Service Queue & Priority], [Integer array `queue[MAX_QUEUE]` with `sortQueue()` handling directional priorities.], [-],
  [6 & 10], [Door & Movement Safety], [Elevator moving transition guarded by `allDoorsClosed()`. Door close guarded by `!overloaded` & `!motion_detected`.], [S1, S2],
  [7 & 12], [Directional Scheduling], [Direction sweep algorithm implemented inside `processQueue()` function.], [-],
  [11], [No move on current floor], [Checked via query ensuring `travelTimer` stays 0 if `targetFloor == current_floor`.], [S4],
  [16-18], [Pick-up/Drop-off operations], [Transition to `floorStop`, broadcasts `urgent elevatorArrivedChannel` to open doors, resets buttons and requests.], [-],
)

== Verification Results

*Safety & Reachability Properties*
+ *D1 (Deadlock Free)*: `A[] not deadlock` 
  _Proves the system control software never reaches a permanent halt state._
+ *S1 (Door Safety)*: `A[] (elevator_manager.inService imply allDoorsClosed())` 
  _Proves it is mechanically impossible for the elevator to move with open doors._
+ *S2 (Overload Safety)*: `A[] not (elevator_manager.inService and overloaded)` 
  _Ensures the elevator remains safely locked at the floor if the weight limit is exceeded._
+ *S4 (No Move on Current Floor)*: `A[] not (elevator_manager.inService and targetFloor == current_floor and elevator_manager.travelTimer > 0)`
  _Due to UPPAAL network synchronization rules, the software momentarily routes through the moving state to broadcast the door-open signal. However, using an `urgent` broadcast channel, this query mathematically proves that physical travel time (`travelTimer > 0`) is strictly impossible when called to the current floor._
+ *R1-R4 (Reachability)*: `E<> (current_floor == 0)`, `E<> (current_floor == 3)`
  _Ensures the extreme floors, moving states, and idle states are fully reachable by the software._

