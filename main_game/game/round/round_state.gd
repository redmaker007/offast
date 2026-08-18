extends Node

## 一天分三段：剧情 → 上班 → 结算。
## 桌面上的物件只在上班时间可以交互，剧情和结算时锁死。
enum Round_State {STORY, GAME, RESULT}
var current_round_state = Round_State.STORY

var save_id := "round_state"


func _ready() -> void:
	add_to_group(SaveState.GROUP)


## 桌面物件能不能点、能不能发光。clickable_item 和 day_clock 都查这个。
func is_interactive() -> bool:
	return current_round_state == Round_State.GAME


func save_data() -> Dictionary:
	return {"current_round_state": current_round_state}


func load_data(d: Dictionary) -> void:
	current_round_state = d.get("current_round_state", Round_State.STORY)
