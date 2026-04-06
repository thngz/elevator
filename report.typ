= Report of the elevator task - Georg Kiviväli
This report will give overview of the main design and decisions made.  It will also contain the requirements traceability matrix and at each automata the picture.

== Design overview

This model consists of 5 main UPPAAL automatons:
+ *ElevatorManager* - Handles main elevator lifecycle
+ *FloorPanel* - The panel which is located on each floor with UP and DOWN buttons
+ *ElevatorPanel* - The panel inside elevator with buttons for different floors
+ *DoorMotorController* - Main controller for doors

*User* automaton interacts with the system.

*OverLoadSensor*, *MotionSensor* and *MaintenanceSensor* are there to non-deterministically simulate overload, motion detection and going into maintenance.


There are also several data structure based components:\
*Global*
+ `bool elevatorButtons[num_floors]` - which buttons in the elevator are pressed (true for pressed)
+ `bool floorDoors[num_floors]` - which floors are opened in each floor
+ `FloorButton floorButtons[num_floors]` - array of structs FloorButton which keep two booleans: up/down. Up being true means that up button has been pressed, same with down button.
+ `DisplayData displayData` - Shared data structure which shows global data where the elevator currently is
+ `int current_floor` - Holds where elevator currently is,
+ `int target_floor` - Holds where elevator needs to go to

*ElevatorManager*
+ `int queue[MAX_QUEUE]` - Holds the requests which are sent to the elevator
== Components

=== ElevatorManager
This automaton controls the main elevator lifecycle.
It consists of four states: ${"noOperations", "inService", "floorStop", "inMaintenance"}$.

ElevatorManager starts at noOperations.

ElevatorManager directly listens to `floorCallChannel[id]` and `goToFloorChannel` to change states.
Those messages are sent by FloorPanel and ElevatorPanel respectively.
On both transitions to inService, the global variable targetFloor is put into the queue.

To ensure passenger comfort and optimize travel time, the ElevatorManager does not simply serve requests First-In-First-Out (FIFO). Instead, `processQueue()` implements a directional sweep optimization (similar to the SCAN scheduling algorithm).

If the elevator is going UP to floor 3 and a user presses the UP button on floor 2, serving floor 2 on the way prevents unnecessary back-and-forth travel. 
To prevent the model from dropping requests or deadlocking when multiple users press buttons simultaneously, the manager utilizes self-loop transitions in both `inService` and `floorStop` states. This design choice ensures the manager remains continuously receptive to the `floorCallChannel` and `goToFloorChannel` regardless of its current lifecycle state.

#figure(
  image("./imgs/elevator_manager.png", width: 80%),
  caption: [ElevatorManager Automaton]
)

=== FloorPanel
The `FloorPanel` is instantiated four times (one for each floor) and handles external passenger requests. 
It utilizes a three-state machine: `Idle`, `ButtonPressed`, and `BothPressed`. It relies on the `floorButtons` array to implicitly represent both the physical button state and the visual LED feedback.

*Why:* This multi-state design explicitly models complex user behavior, particularly when passengers waiting at the same floor want to go in opposite directions. 
To handle this fairly, the automaton introduces a local `sentUp` boolean toggle. If both the UP and DOWN buttons are pressed (entering the `BothPressed` state), the panel does not clear both requests at once when the elevator arrives. Instead, it clears only the direction that was serviced first, toggles `sentUp`, and keeps the other request active for the next elevator visit. This guarantees alternating service and prevents starvation for passengers waiting to go in the opposite direction.

#figure(
  image("./imgs/floor_panel.png", width: 60%),
  caption: [FloorPanel Automaton]
)

=== ElevatorPanel
The `ElevatorPanel` resides inside the carriage and manages internal floor selections. 
It is structured as a sequential three-state machine: `Idle` $->$ `ButtonPressed` $->$ `Ready`. 

This strict sequence models the physical workflow of a passenger entering the cabin. When a floor is selected (moving to `ButtonPressed`), the panel immediately sends a synchronization signal over `doorCloseChannel` to the DoorMotorController. This simulates the real-world behavior where pressing an internal floor button actively encourages the doors to begin their closing sequence. The panel then waits in the `Ready` state until the `elevatorArrivedChannel` broadcast is received, at which point it clears the request and returns to `Idle`. This prevents button-spamming inside the cabin from flooding the ElevatorManager with redundant requests.

#figure(
  image("./imgs/elevator_panel.png", width: 60%),
  caption: [ElevatorPanel Automaton]
)

=== DoorMotorController
The `DoorMotorController` governs the physical opening and closing of the elevator doors using a strict time-bound automaton (`doorTimer`).
*Why:* Separating the door logic from the `ElevatorManager` is a crucial safety decision. The manager only dictates *when* the elevator arrives at a floor, but the door controller independently enforces safety limits. 

The controller rests in `Idle` and transitions to `DoorOpen` upon receiving the `elevatorArrivedChannel` broadcast. It automatically attempts to close the door after `DOOR_TIMEOUT`. However, the return transition is strictly guarded by `!motion_detected` and `!overloaded`. 
*Why:* By embedding these constraints at the door-motor level, it becomes physically impossible for the doors to close if the doorway is obstructed or the cabin is too heavy. Since the `ElevatorManager` cannot enter `inService` (moving state) unless `allDoorsClosed()` returns true, this architectural hierarchy guarantees adherence to critical safety properties (S1 & S2).

#figure(
  image("imgs/door_motor_controller.png", width: 70%),
  caption: [DoorMotorController Automaton]
)

=== Environmental Sensors (Overload, Motion, Maintenance)
The `OverloadSensor`, `MotionSensor`, and `MaintenanceSwitch` simulate unpredictable environmental factors.
Initially, these sensors were implemented as pure non-deterministic toggles. However, this caused verification failures (Zeno behaviors and race conditions), as UPPAAL could theoretically toggle "overloaded" on and off infinitely within zero time units.
*Why:* To create a physically realistic model, local clocks (`overloadTimer`, `motionTimer`) were added. A sensor can now only trigger a state change after a minimum time has elapsed, simulating the physical time it takes for passengers to enter or exit the cabin. Furthermore, guards were added to force both sensors to reset to a safe state (`false`) the moment the doors close, preventing the system from registering phantom obstructions while moving.

== Requirements Traceability Matrix

To ensure all assignment requirements are met and formally verified, the following matrix maps the functional requirements to their UPPAAL implementation and corresponding CTL queries.

#table(
  columns: (auto, 1fr, 1.5fr, auto),
  align: (center, left, left, center),
  fill: (col, row) => if row == 0 { luma(220) } else { white },
  
  [*Req ID*], [*Description*], [*Implementation Logic*], [*Query ID*],
  
  [1], [Elevator Manager States], [Implemented as 4 locations in `ElevatorManager`: `noOperations`, `inService`, `floorStop`, `inMaintenance`.], [R2, R3],
  [2 & 5], [LED Indicators Display], [Implicitly tracked via `floorButtons[id].up/down` and `elevatorButtons` booleans. Turning true represents the LED glowing.], [L1],
  [3 & 4], [Service Queue & Priority], [Integer array `queue[MAX_QUEUE]` with `sortQueue()` handling directional priorities.], [-],
  [6 & 10], [Door & Movement Safety], [Elevator moving transition guarded by `allDoorsClosed()`. Door close guarded by `!overloaded` & `!motion_detected`.], [S1, S2],
  [7 & 12], [Directional Scheduling], [Direction sweep algorithm implemented inside `processQueue()` function.], [L1, L2],
  [11], [No move on current floor], [Handled mathematically in `processQueue()` and verified via formal query constraint.], [S4],
  [16-18], [Pick-up/Drop-off operations], [Transition to `floorStop`, broadcasts `elevatorArrivedChannel` to open doors, resets buttons/LEDs and requests.], [L3],
)

== Verification Results

All required properties were successfully verified in UPPAAL. Below is the list of formalized CTL queries proving system correctness:

*Safety Properties (Must never violate)*
+ *D1 (Deadlock)*: `A[] not deadlock` 
  _Proves the system never reaches a halt state._
+ *S1 (Door Safety)*: `A[] (elevator_manager.inService imply allDoorsClosed())` 
  _Ensures mechanical impossibility of moving with open doors._
+ *S2 (Overload Safety)*: `A[] not (elevator_manager.inService and overloaded)` 
  _Ensures the elevator remains locked at the floor if weight limit is exceeded._
+ *S4 (Logic Safety)*: `A[] not (elevator_manager.inService and targetFloor == current_floor and travelTimer > 0)` 
  _Elevator does not attempt to move to a floor it is already stationed at._

*Liveness & Reachability Properties (Eventual behaviors)*
+ *L1 (Service Guarantee)*: `floorButtons[1].up --> elevator_manager.floorStop and current_floor == 1` 
  _If a floor calls for an elevator (LED glows), it will eventually stop at that floor._
+ *L2 (Stop Guarantee)*: `elevator_manager.inService --> elevator_manager.floorStop` 
  _The elevator will eventually finish moving and open its doors._
+ *L3 (Door Closing)*: `door_motor_controller.DoorOpen --> door_motor_controller.Idle`
  _Doors will eventually close (assuming passengers clear the motion/overload sensors)._
+ *R1-R4 (Reachability)*: `E<> (current_floor == 0)`, `E<> (current_floor == 3)`
  _Ensures extreme floors and specific idle/moving states are mathematically possible to reach._
