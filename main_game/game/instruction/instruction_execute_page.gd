extends popup_window

## 答题窗口。开关动画在 popup_window 里，这里只管什么时候该开、以及显示什么题目。


func _ready() -> void:
	super()
	SignalBus.round_state_change.connect(on_round_state_change)
	# 题目由窗口自己订阅，数据层不再直接往这里的 Label 写字。
	SignalBus.show_question.connect(on_show_question)
	SignalBus.game_restored.connect(on_game_restored)


func on_round_state_change(rs:RoundState.Round_State):
	if rs == RoundState.Round_State.EXECUTING_INSTRUCTION:
		WindowManager.open_window(self)


func on_game_restored():
	# 读档之后要按恢复出来的回合状态决定该不该开，判断和上面完全一样。
	on_round_state_change(RoundState.current_round_state)


func on_show_question(question_text:String):
	%instruction_text.text = question_text
