extends Node
class_name round_manager

var current_round_num :=0

var current_round_employee_name_list = []

var save_id := "round_manager"


func _ready() -> void:
	add_to_group(SaveState.GROUP)
	SignalBus.all_email_read.connect(next_state)
	SignalBus.all_question_answered.connect(start_new_round)


func save_data() -> Dictionary:
	return {
		"current_round_num": current_round_num,
		"current_round_employee_name_list": current_round_employee_name_list,
	}


func load_data(d: Dictionary) -> void:
	current_round_num = d.get("current_round_num", 0)
	current_round_employee_name_list = d.get("current_round_employee_name_list", [])

func start_new_round():
	current_round_num +=1
	print("New round! Round "+str(current_round_num)+"!")
	if %instruction_execute_manager.total_correct_num != 0:
		print("Total correct number:"+str(%instruction_execute_manager.total_correct_num))
	
	change_state(RoundState.Round_State.RECEIVING_EMAIL)

func change_state(_round_state:RoundState.Round_State):
	RoundState.current_round_state = _round_state
	enter_state(RoundState.current_round_state)
	

func next_state():
	change_state((RoundState.current_round_state+1)%RoundState.Round_State.size())

func enter_state(_round_state:RoundState.Round_State):
	match _round_state:
		RoundState.Round_State.RECEIVING_EMAIL:
			
			current_round_employee_name_list = %email_generator.get_random_employee_name(3)
			for i in range(7):
				%email_generator.generate_email(current_round_employee_name_list)
		RoundState.Round_State.EXECUTING_INSTRUCTION:
			SignalBus.start_to_execute_instruction.emit()
	SignalBus.round_state_change.emit(_round_state)
