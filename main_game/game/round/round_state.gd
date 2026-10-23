extends Node

## 一天分三段：剧情 → 上班 → 结算。
## 桌面上的物件只在上班时间可以交互，剧情和结算时锁死。
enum Round_State {STORY, GAME, RESULT}
var current_round_state = Round_State.STORY

var save_id := "round_state"


func _ready() -> void:
	add_to_group(SaveState.GROUP)


## 临时把交互锁住的东西（比如正在播的 cutscene）。上班时间里只要有人锁着，
## is_interactive() 也是 false——物件点不了、时钟也停。不存档：读回来的局面不会带着锁。
var _lock_holders: Dictionary = {}


## 桌面物件能不能点、能不能发光。clickable_item 和 day_clock 都查这个。
func is_interactive() -> bool:
	return current_round_state == Round_State.GAME and _lock_holders.is_empty()


## 加一把锁。同一个 holder 重复加只算一把。
func lock_interaction(holder: Object) -> void:
	if _lock_holders.has(holder):
		return
	_lock_holders[holder] = true
	if _lock_holders.size() == 1:
		SignalBus.interaction_lock_changed.emit(true)


## 解掉 holder 加的那把锁，没加过就什么都不做。
func unlock_interaction(holder: Object) -> void:
	if not _lock_holders.erase(holder):
		return
	if _lock_holders.is_empty():
		SignalBus.interaction_lock_changed.emit(false)


func save_data() -> Dictionary:
	return {"current_round_state": current_round_state}


func load_data(d: Dictionary) -> void:
	current_round_state = d.get("current_round_state", Round_State.STORY)
