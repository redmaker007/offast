extends Node
class_name instruction_execute_manager

var question_box = []

var current_question:=[]

var total_correct_num :=0

var save_id := "instruction_execute_manager"

func _ready() -> void:
	add_to_group(SaveState.GROUP)
	SignalBus.start_to_execute_instruction.connect(_start_to_execute_instruction)
	SignalBus.game_restored.connect(_on_game_restored)


func save_data() -> Dictionary:
	return {
		"question_box": question_box,
		"current_question": current_question,
		"total_correct_num": total_correct_num,
	}


func load_data(d: Dictionary) -> void:
	question_box = d.get("question_box", [])
	current_question = d.get("current_question", [])
	total_correct_num = d.get("total_correct_num", 0)


func _on_game_restored():
	if current_question:
		SignalBus.show_question.emit(current_question[0])

func _start_to_execute_instruction():
	total_correct_num = 0
	var _instruction_box = %instruction_box.take_out_instruction()
	
	for key in _instruction_box:
		question_box.append(generate_question(_instruction_box[key]))
	next_question()

func generate_question(_instruction: f_instruction):
	var output_question
	var ans: bool
	var n = _instruction.target_employee_name

	if _instruction.has_fire:
		var r = pick_one(3)
		output_question = [
			"Should we fire " + n + "?",
			"Should we let " + n + " go?",
			"Should we terminate " + n + "?"
		][r]
		ans = true

	elif _instruction.has_raise and _instruction.has_promotion:
		var r = pick_one(3)
		output_question = [
			"Should we give " + n + " a raise and promote them?",
			"Should we give " + n + " a reduction?",
			"Should we fire " + n + "?"
		][r]
		ans = [true, false, false][r]

	elif _instruction.has_raise:
		var r = pick_one(3)
		output_question = [
			"Should we give " + n + " a raise?",
			"Should we give " + n + " a promotion?",
			"Should we give " + n + " a reduction?"
		][r]
		ans = [true, false, false][r]

	elif _instruction.has_promotion:
		var r = pick_one(3)
		output_question = [
			"Should we promote " + n + "?",
			"Should we give " + n + " a raise?",
			"Should we demote " + n + "?"
		][r]
		ans = [true, false, false][r]

	elif _instruction.has_reduction:
		var r = pick_one(3)
		output_question = [
			"Should we give " + n + " a pay reduction?",
			"Should we give " + n + " a raise?",
			"Should we promote " + n + "?"
		][r]
		ans = [true, false, false][r]

	return [output_question, ans]

func pick_one(n: int) -> int:
	return randi() % n


func next_question():
	if not question_box:
		SignalBus.all_question_answered.emit()
		return
	current_question = question_box.pop_front()
	SignalBus.show_question.emit(current_question[0])




func _on_yes_butt_pressed() -> void:
	if RoundState.current_round_state != RoundState.Round_State.EXECUTING_INSTRUCTION:
		return
	check_correctness(true)
	next_question()


func _on_no_butt_pressed() -> void:
	if RoundState.current_round_state != RoundState.Round_State.EXECUTING_INSTRUCTION:
		return
	check_correctness(false)
	next_question()

func check_correctness(ans:bool):
	if current_question[1] == ans:
		total_correct_num +=1
		print("Correct!")
		return true
	print("Wrong!")
	return false
	pass
