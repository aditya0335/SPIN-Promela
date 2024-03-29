bit lift_switch[3] // Switches present in the elevator
bit floor_switch[3] // Switches present on the floors

bit door_state // 1 for open and 0 for closed

byte curr_floor // current floor of the elevator - Should take values 0, 1, 2

bit motion_direction // 0 for down, 1 for up

// Type of messages to be passed among the processes
mtype = {open_door, close_door, move_up, move_down, stop, press_floor_button, press_elevator_button}

// Channel definitions
chan to_elevator = [0] of { mtype } // Channel to send instructions from controller to elevator
chan button_press = [0] of { mtype, byte} // Channel to record button presses

// Models the elevator controller
active proctype elevator_controller()
{
	curr_floor = 0
	motion_direction = 0 // Initially assumed to be going downwards

start: 
	if
	:: lift_switch[0] == 1 || lift_switch[1] == 1 || lift_switch[2] == 1 -> goto close_elevator_doors
	:: floor_switch[0] == 1 || floor_switch[1] == 1 || floor_switch[2] == 1 -> goto close_elevator_doors
	fi
	
close_elevator_doors: 
	to_elevator!close_door // Instruct the elevator to close doors

check_direction: 
progress_change_direction:
	if 
	:: curr_floor == 0 -> motion_direction = 1 -> goto halt_and_change_dir // If at lowest floor, move up
	:: curr_floor == 2 -> motion_direction = 0 -> goto halt_and_change_dir // If at highest floor, move down
	:: else -> goto move_up_or_down
	fi

halt_and_change_dir: 
	to_elevator!stop

move_up_or_down:
	if
	:: motion_direction == 0 && door_state == 0 -> goto downward_motion
	:: motion_direction == 1 && door_state == 0 -> goto upward_motion
	fi

upward_motion:
progress_up:
	curr_floor = curr_floor + 1;
	to_elevator!move_up; // Instruct the elevator to move up
	goto check_open_or_change_direction

downward_motion:
progress_down:
	curr_floor = curr_floor - 1;
	to_elevator!move_down; // Instruct the elevator to move downwards
	goto check_open_or_change_direction

check_open_or_change_direction:
	if
	:: lift_switch[curr_floor] == 1 -> to_elevator!stop -> goto unpress_button
	:: floor_switch[curr_floor] == 1 -> to_elevator!stop -> goto unpress_button
	:: else -> goto check_direction
	fi

unpress_button:
	lift_switch[curr_floor] = 0; floor_switch[curr_floor] = 0; to_elevator!open_door;
	goto start
}

// Models the elevator
active proctype elevator()
{
	door_state = 1

start:
	to_elevator?close_door -> door_state = 0; goto wait_for_move // Close door and update door state

wait_for_move:
	if
	:: to_elevator?move_up -> goto moving_upward
	:: to_elevator?move_down -> goto moving_downward
	:: to_elevator?stop -> goto wait_for_move // To handshake with direction changing halts
	:: to_elevator?open_door -> door_state = 1 -> goto start
	fi

moving_upward:
	if
	:: to_elevator?move_up -> goto moving_upward
	:: to_elevator?stop -> goto wait_for_move
	fi

moving_downward:
	if
	:: to_elevator?move_down -> goto moving_downward
	:: to_elevator?stop -> goto wait_for_move
	fi
}

// Models the elevator button presses
active [3] proctype press_elevator_buttons()
{
start:
	button_press!press_elevator_button(_pid % 3) -> goto start
}

// Models the floor button presses
active [3] proctype press_floor_buttons()
{
start:
	button_press!press_floor_button(_pid % 3) -> goto start
}

// Records the button presses for the controller
active proctype record_button_presses()
{
	byte i;
	floor_switch[0] = 0; floor_switch[1] = 0; floor_switch[2] = 0;
	lift_switch[0] = 0; lift_switch[1] = 0; lift_switch[2] = 0;

start:
	if
	:: button_press?press_floor_button(i) -> floor_switch[i] = 1
	:: button_press?press_elevator_button(i) -> lift_switch[i] = 1
	fi
	goto start
}

// LTL Properties specification

// 1. Current floor number always stays between 0 and 2
ltl valid_range 
{ 
	[] 
	(curr_floor >= 0 && curr_floor <= 2)
}

// 2. The elevator never moves with its doors open
ltl door_closed_in_motion 
{ 
	[] 
	(
		!(door_state == 1 && (elevator_controller[0]@upward_motion || elevator_controller[0]@downward_motion))
	)
}

// 3. The elevator visits every floor infinitely often (Proved using 'progress' labels)

// 4. Requests to use the elevator are eventually serviced
ltl elevator_use_serviced
{
	[]
	(
		((floor_switch[0] == 1) -> <> (curr_floor == 0 && elevator_controller[0]@start)) &&
		((floor_switch[1] == 1) -> <> (curr_floor == 1 && elevator_controller[0]@start)) &&
		((floor_switch[2] == 1) -> <> (curr_floor == 2 && elevator_controller[0]@start))
	)
}

// 5. Requests to be delivered to a particular floor are eventually serviced
ltl floor_reach_serviced
{
	[]
	(
		((lift_switch[0] == 1) -> <> (curr_floor == 0 && elevator_controller[0]@start)) &&
		((lift_switch[1] == 1) -> <> (curr_floor == 1 && elevator_controller[0]@start)) &&
		((lift_switch[2] == 1) -> <> (curr_floor == 2 && elevator_controller[0]@start))
	)
}

