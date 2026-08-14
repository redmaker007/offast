extends Node



var save_id := "email_reader"

var unread_email = []
var read_email = []


func _ready() -> void:
	add_to_group(SaveState.GROUP)
	SignalBus.send_email.connect(receive_email)
	SignalBus.round_state_change.connect(email_reading_time)
	SignalBus.game_restored.connect(on_game_restored)

func email_reading_time(rs:RoundState.Round_State):
	if rs == RoundState.Round_State.RECEIVING_EMAIL:
		if unread_email:
			read_next_email()

func read_next_email():
	if unread_email:
		var current_email = unread_email.pop_front()
		SignalBus.read_a_email.emit(current_email)
		read_email.append(current_email)
		SignalBus.show_email.emit(current_email)
	else:
		SignalBus.all_email_read.emit()
		pass


func receive_email(e:email):
	unread_email.append(e)


func save_data() -> Dictionary:
	return {
		"unread_email": unread_email,
		"read_email": read_email,
	}


func load_data(d: Dictionary) -> void:
	unread_email = d.get("unread_email", [])
	read_email = d.get("read_email", [])


func on_game_restored():
	# 只重发 UI 侧的信号：read_a_email 会让 instruction_box 再累加一次指令。
	if read_email:
		SignalBus.show_email.emit(read_email.back())


func _on_button_pressed() -> void:
	if RoundState.current_round_state != RoundState.Round_State.RECEIVING_EMAIL:
		return
	read_next_email()
