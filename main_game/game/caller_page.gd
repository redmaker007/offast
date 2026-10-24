extends popup_window

## 桌上那台电话：**拨号**。
##
## 号码每局随机，写在别人给你的邮件/对话里，玩家自己抄进记事本再拨过来。
## 拨对了就接通（对话在 event_page 里播，和桥段共用一套气泡）；
## 拨错了只有忙音——不提示「差一位」，不列已知号码，记不住就回去翻本子。
##
## 点电话不一定弹这个：要看当天的天内图。现有内容是「今天的来电还没接就先播来电，
## 接过了才是拨号盘」，图上用视窗 bubble 调 open_dialer() 打开这里。

const MAX_DIGITS := 6


func _ready() -> void:
	super()
	%dial_input.max_length = MAX_DIGITS
	%dial_input.text_submitted.connect(_on_submitted)
	SignalBus.round_state_change.connect(_on_round_state_change)
	%dial_status.text = ""


func _on_round_state_change(_rs) -> void:
	_clear()


func _clear() -> void:
	%dial_input.text = ""
	%dial_status.text = ""


## 打开拨号盘（天内图的视窗 bubble 调）。
func open_dialer() -> void:
	_clear()
	await open()


func _on_submitted(_text: String) -> void:
	_dial()


func _on_call_pressed() -> void:
	_dial()


func _on_close_pressed() -> void:
	close()


func _dial() -> void:
	var who: contact = %story_book.contact_by_number(%dial_input.text)
	if who == null:
		%dial_status.text = tr("UI_NO_ANSWER")
		return
	%dial_status.text = ""
	# 记下打通过谁：条件 called(米拉) 查的就是这个。
	GameState.mark_called(who.contact_name)
	await close()
	%event_page.play_conversation(who.call, &"call", who.contact_name)
