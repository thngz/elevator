= Elevator system requirements

Elevator system used in this project must obey the following specification, which is divided into *functional*, *safety* and *comfort* specifications:

// what the system does
== Functional

=== Elevator manager
Elevator manager is the main controller of the elevator.
It's task is to orchestrates all other components. 
At any given time the manager is in one of the following four states: 

+ *inService* - Normal operation
+ *floorStop* - Stopped at a floor for passengers
+ *noOperations* - Idle state
+ *inMaintenance* - Under maintenace

=== Floor panel
Floor panel component shows the call elevator buttons (UP/DOWN). Floor panels are the main interfaces through which elevator is operated by passengers. Each floor has one panel and it must display current floor number. Once the elevator arrives at the current floor, the LED indicator of the panel must turn off.

To call the elevator, user needs to press the call button at any given floor. In the system this sends a `floorCall` message to the service queue.

=== Floor display
Floor display is a small component on each floor that shows on which floor the elevator is, and which direction its moving (UP/DOWN).

=== Elevator panel
Elevator panel component contains the buttons inside the elevator which passengers can use to select which floor they want to go to. In the system, interactions with the panel send an `elevatorCall` request to the service queue.

=== Elevator display
Elevator display component shows the current floor and direction (UP/DOWN) inside the elevator. When any button is pressed the display should update to reflect the latest state.

=== Floor and elevatorCall Requests
The `floorCall` and `elevatorCall` requests are put to a service queue to be later consumed by main controller. Each call is assigned a direction. Motor controller (which controls the motor for door operations) latches when Direction and Enable signals are received.

The service requests must be optimized. Meaning that for instance, ascending requests are handled when elevator is going UP (When the elevator is going UP from floor 1 to floor 3, it can service floor 2 request on the way). Likewise with downward requests.

Requests can have priorities.
=== Pick-up and drop-off operations

When picking up or dropping off passengers, the current floor must be de-registered from the queue, elevator manager's operating mode must be set to *idle*, door status must be set to *open*. The elevator must not move during the operation. Once its complete, elevator status must be updated and rest of the queue processed.

=== Main motor controller
Main motor controller controls the carriage movement throughout the floors. 

// what must never happen
== Safety
The elevator should only move if the door is closed, floor button pressed, elevator is not overloaded and no stopping operation is initiated.

The door must close if and if user presses the door close button or user has selected a floor, waited the timeout and motion detector shows no-one entering

The elevator must also *NOT* move if user selects the current floor.

// nice to have behaviors
== Comfort

=== Floor panel
When *UP* button is pressed, *UP* LED will glow. 
When *DOWN* button is pressed, *DOWN* LED will glow. 

These lights can glow simultaneously.

= Components

The elevator control system consists of *10 components*. The elevator operates on *4 floors*.

== Active components (automata)
1) *Elevator manager*:
#block([
  *Inputs*: Request from service queue (`floorCall`, `elevatorCall`)

  *Outputs*: `elevator_goto` to the main motor controller and to door motor controller to close the doors.
  
])

2) *Floor panel*:
#block([
  *Inputs*: `floor_request` message
  
  *Outputs*: `floorCall` message to the Service Queue
])

3) *Floor door*:
#block([
  *Inputs*: `door_close` message from the door motor controller  

  *Outputs*: Set door to closed
])

4) *Elevator panel*:
#block([
  *Inputs*: `elevator_request` message from the user
  
  *Outputs*: `elevatorCall` message to the Service Queue
])

5) *Door motor controller*:
#block([
  *Inputs*: `elevator_goto` message from the elevator manager OR `door_close` message from the user.
  
  *Outputs*: `door_close` message to the Floor panel
])

6) *Main motor controller*:
#block([
  *Inputs*: `elevator_goto` message from the elevator manager   
  *Outputs*: Moves the carriage to the location specified by the `elevator_goto` message
])

7) *Service queue*:
#block([
  *Inputs*: `elevatorCall` message from elevator panel OR `floorCall` message from the floor panel
  
  *Outputs*: Places the message to the queue for later processing
])

== Passive components (data structures)
+ Floor display: Struct of integer, boolean (0 for down, 1 for up)
+ Elevator display: Struct integer, boolean (0, for down, 1 for up)
+ Overload sensor: boolean (0 for not overloaded, 1 for overloaded)
+ Door motion detector: (0 for motion not detected, 1 for motion detected)
+ Buttons inside elevator: Array of bools where each bool corresponds to whether or not the button is pressed or not. Index of the button corresponds to the floor number. 

+ Buttons on each floor: Struct pair (bool, bool) where pair[0] shows if down button is pressed, pair[1] shows if up button is pressed

+ Lift carriage location (which floor it is in): Array of bools[4], in which each bool corresponds if carriage is at that floor or not

+ Door closed/opened at each floor: Array of bools[4] in which each bool corresponds to whether or not door at that floor is open or not
