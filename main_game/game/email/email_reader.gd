extends Node

## 收件箱。邮件阅后即焚——公司保密要求，读过的信当场销毁，
## 没有第二次查看的机会。所以这里只有一个待读队列，没有已读列表。

var save_id := "email_reader"

var unread_email = []


func _ready() -> void:
	add_to_group(SaveState.GROUP)
	# 条件 inbox_empty 靠这个组找到收件箱。
	add_to_group(story_condition.INBOX_GROUP)
	SignalBus.send_email.connect(receive_email)


func receive_email(e:email):
	unread_email.append(e)


## 每天开工前清空，隔夜邮件不保留。
func clear_inbox() -> void:
	unread_email.clear()


func remaining() -> int:
	return unread_email.size()


func read_next_email() -> void:
	if unread_email.is_empty():
		SignalBus.inbox_empty.emit()
		return
	# pop 出来这封信就不存在了：show_email 让邮件页显示一次，之后任何地方都找不回来。
	# 指令不在这里记——instruction_box 在邮件发出时就记好了，
	# 读不读只影响玩家知不知道，不影响标准答案。
	var current_email = unread_email.pop_front()
	SignalBus.show_email.emit(current_email)


func save_data() -> Dictionary:
	return {"unread_email": unread_email}


func load_data(d: Dictionary) -> void:
	unread_email = d.get("unread_email", [])


func _on_button_pressed() -> void:
	if not RoundState.is_interactive():
		return
	read_next_email()
