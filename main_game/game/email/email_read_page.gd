extends popup_window

## 读邮件的窗口。开关动画在 popup_window 里，这里只管什么时候该开、以及显示什么内容。


func _ready() -> void:
	super()
	SignalBus.round_state_change.connect(on_round_state_change)
	SignalBus.open_email_window_request.connect(on_open_request)
	# 邮件内容由窗口自己订阅，数据层不再直接往这里的 Label 写字。
	SignalBus.show_email.connect(on_show_email)
	SignalBus.game_restored.connect(on_game_restored)


func on_round_state_change(rs:RoundState.Round_State):
	if rs == RoundState.Round_State.RECEIVING_EMAIL:
		WindowManager.open_window(self)


func on_game_restored():
	# 读档之后要按恢复出来的回合状态决定该不该开，判断和上面完全一样。
	on_round_state_change(RoundState.current_round_state)


func on_open_request():
	if RoundState.current_round_state == RoundState.Round_State.RECEIVING_EMAIL:
		WindowManager.open_window(self)


func on_show_email(e:email):
	%email_content.text = _format_email(e)


func _format_email(e:email) -> String:
	var output :String = ""
	match e.instruction:
		"Fire":
			output = "Fire "+e.target_employee_name+"."
		"Raise":
			output = "Give "+e.target_employee_name+" a raise."
		"Reduction":
			output = "Give "+e.target_employee_name+" a reduction."
		"Promotion":
			output = "Give "+e.target_employee_name+" a promotion."
	return output+" Level:"+str(e.sender_class)+"."
