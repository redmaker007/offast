extends Node


enum Round_State {RECEIVING_EMAIL, EXECUTING_INSTRUCTION}
var current_round_state = Round_State.RECEIVING_EMAIL

var save_id := "round_state"


func _ready() -> void:
	add_to_group(SaveState.GROUP)


func save_data() -> Dictionary:
	return {"current_round_state": current_round_state}


func load_data(d: Dictionary) -> void:
	current_round_state = d.get("current_round_state", Round_State.RECEIVING_EMAIL)
