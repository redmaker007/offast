extends Label

## 桌面角落的上班时钟。只在 GAME 段显示。


func _ready() -> void:
	text = ""
	visible = false
	SignalBus.day_time_changed.connect(_on_day_time_changed)
	SignalBus.round_state_change.connect(_on_round_state_change)


func _on_day_time_changed(clock_text: String, _ratio: float) -> void:
	text = clock_text


func _on_round_state_change(rs) -> void:
	visible = rs == RoundState.Round_State.GAME
