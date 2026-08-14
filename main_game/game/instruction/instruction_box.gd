extends Node

var instruction_box = {}

var save_id := "instruction_box"

func _ready() -> void:
	add_to_group(SaveState.GROUP)
	SignalBus.read_a_email.connect(append_instruction)


func save_data() -> Dictionary:
	return {"instruction_box": instruction_box}


func load_data(d: Dictionary) -> void:
	instruction_box = d.get("instruction_box", {})


func append_instruction(e:email):
	var i = is_already_in_instruction_box(e)
	if i:
		i.change_instruction(e.instruction,e.sender_class)
	
	else:
		i = f_instruction.new()
		i.init_instruction(e.instruction,e.target_employee_name,e.sender_class)
		instruction_box[e.target_employee_name] = i
	pass


func is_already_in_instruction_box(e:email):
	if e.target_employee_name in instruction_box:
		return instruction_box[e.target_employee_name]
	return null

func take_out_instruction():
	var i = instruction_box.duplicate()
	instruction_box.clear()
	return i
