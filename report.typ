= Report of the elevator task - Georg Kiviväli
This report will give overview of the main design and decisions made.  It will also contain the requirements traceability matrix and at each automata the picture.

== Design overview

This model consists of 5 main UPPAAL automatons:
+ *ElevatorManager* - Handles main elevator lifecycle
+ *FloorPanel* - The panel which is located on each floor with UP and DOWN buttons
+ *ElevatorPanel* - The panel inside elevator with buttons for different floors
+ *DoorMotorController* - Main controller for doors
+ *ServiceQueue* - Handles appending requests to queue and notifying the *ElevatorManager* of new requests.

And an *User* automaton that interacts with the system.

There are also several data structure based components:\
*Global*
+ `bool elevatorButtons[num_floors]` - which buttons in the elevator are pressed (true for pressed)
+ `bool floorDoors[num_floors]` - which floors are opened in each floor
+ `FloorButton floorButtons[num_floors]` - array of structs FloorButton which keep two booleans: up/down. Up being true means that up button has been pressed, same with down button.
+ `FloorCall floorCall` - Shared data structure which is updated when button is pressed on any floor panel. Stores where the request came and which direction to go to.
+ `GotoFloor` - Shared data structure which is updated when button is pressed inside the elevator panel. Stores the floor to which to go.

=== ElevatorManager

This automaton controls the main elevator lifecycle.
It consists of four states: ${"noOperations", "inService", "floorStop", "inMaintenance"}$.


