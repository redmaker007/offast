extends PanelContainer

## 日终结算：全屏覆盖，显示当天对了几个、错了几个、扣没扣命。
##
## 它不自己判分——round_manager 算完之后通过 day_result_ready 把结果送过来。


func _ready() -> void:
	visible = false
	SignalBus.day_result_ready.connect(_on_day_result_ready)
	SignalBus.round_state_change.connect(_on_round_state_change)


func _on_round_state_change(rs) -> void:
	# 离开 RESULT 段就收起来（正常是玩家点继续时已经收了，这里兜底）。
	if rs != RoundState.Round_State.RESULT:
		visible = false


func _on_day_result_ready(result: Dictionary) -> void:
	%result_title.text = tr("UI_DAY_COUNT") % [result.get("day", 0), result.get("days_to_win", 0)]
	%result_correct.text = "%d / %d" % [result.get("correct", 0), result.get("total", 0)]
	%result_wrong.text = "%d" % result.get("wrong", 0)
	%result_lives.text = tr("UI_LIVES_LEFT") % result.get("lives", 0)
	# 一个没错的日子不用挂这句，留白本身就是"今天没事"。
	%result_note.visible = int(result.get("wrong", 0)) > 0
	visible = true


func _on_continue_pressed() -> void:
	visible = false
	SignalBus.result_confirmed.emit()
