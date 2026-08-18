extends PanelContainer

## 邮件页：笔记本的第一个 app。
##
## 邮件阅后即焚，所以这里不缓存任何内容——显示过的信在数据层已经不存在了，
## 换页、换天、读档之后一律清空，不给玩家"翻回去看一眼"的机会。

const EMPTY_TEXT := "Inbox empty."


func _ready() -> void:
	SignalBus.show_email.connect(on_show_email)
	SignalBus.inbox_empty.connect(_on_inbox_empty)
	SignalBus.round_state_change.connect(_on_round_state_change)
	SignalBus.game_restored.connect(_clear)


func _on_round_state_change(_rs) -> void:
	# 新的一天换一批邮件，上一天残留的内容不该还挂在屏幕上。
	_clear()


func _clear() -> void:
	%email_content.text = ""


func _on_inbox_empty() -> void:
	%email_content.text = EMPTY_TEXT


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
