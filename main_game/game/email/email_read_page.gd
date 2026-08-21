extends PanelContainer

## 邮件页：笔记本的第一个 app。
##
## 邮件阅后即焚，所以这里不缓存任何内容——显示过的信在数据层已经不存在了，
## 换页、换天、读档之后一律清空，不给玩家"翻回去看一眼"的机会。
##
## 剧情信多两样东西：发件人身份和回复选项。**没回完不许读下一封**——
## 回复是表态，跳过就等于没表态，那两派拉拢玩家这条线就断了。
## 回复过的信照样不留档，回显的那句话下一封信一来就没了。

## 当前这封信的定义（剧情信才有）。回复按钮按它生成。
var _def: email_def = null


func _ready() -> void:
	SignalBus.show_email.connect(on_show_email)
	SignalBus.inbox_empty.connect(_on_inbox_empty)
	SignalBus.round_state_change.connect(_on_round_state_change)
	SignalBus.game_restored.connect(_clear)
	_clear()


func _on_round_state_change(_rs) -> void:
	# 新的一天换一批邮件，上一天残留的内容不该还挂在屏幕上。
	_clear()


func _clear() -> void:
	%email_content.text = ""
	%sender_name_text.text = ""
	_def = null
	_clear_replies()
	_set_locked(false)


func _on_inbox_empty() -> void:
	_clear()
	%email_content.text = tr("UI_INBOX_EMPTY")


func on_show_email(e:email):
	_def = %story_book.mail_def(e.id) if e.is_scripted() else null
	_clear_replies()

	if _def == null:
		%sender_name_text.text = str(e.sender)
		%email_content.text = _format_email(e)
		_set_locked(false)
		return

	%sender_name_text.text = _def.sender_name
	%email_content.text = _format_def(_def, e)

	# 已经回过的信（读档回来又读了一遍）不再问一次，也不再加一次分。
	if _def.can_reply() and not GameState.is_email_answered(_def.id):
		_build_replies(_def)
		_set_locked(true)
	else:
		_set_locked(false)

	%profile_button.visible = not String(_def.about_employee).is_empty()


## 随机信：只有一句干巴巴的指令，格式和加剧情之前一模一样。
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


## 剧情信：标题 + 正文，末尾附上人事指令那一行（有的话），
## 指令那句用的还是随机信的措辞——玩家不该从行文风格判断哪封信"更重要"。
func _format_def(d: email_def, e: email) -> String:
	var lines: Array[String] = []
	if not d.subject.is_empty():
		lines.append(d.subject)
	var body := d.body_text()
	if not body.is_empty():
		lines.append(body)
	if d.has_order():
		lines.append(_format_email(e))
	# {caller:米拉} 之类的占位符换成这一局的真号码。
	return story_text.resolve("\n\n".join(lines))


# ── 回复 ────────────────────────────────────────────────

func _build_replies(d: email_def) -> void:
	for i in range(d.replies.size()):
		var r: email_reply = d.replies[i]
		if r == null:
			continue
		var b := Button.new()
		b.text = r.text
		b.custom_minimum_size = Vector2(320, 44)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.theme_type_variation = &"LongButton"
		b.pressed.connect(_on_reply_pressed.bind(i))
		%reply_list.add_child(b)
	%reply_list.visible = true


func _on_reply_pressed(index: int) -> void:
	if _def == null or index < 0 or index >= _def.replies.size():
		return
	var r: email_reply = _def.replies[index]
	_clear_replies()
	_set_locked(false)

	GameState.apply_effect(r.effect if r != null else null)
	GameState.mark_email_answered(_def.id)
	SignalBus.email_replied.emit(_def.id, r)

	# 回显只是给玩家一个"这封信我回了什么"的即时反馈，不留档。
	if r != null and r.effect != null and not r.effect.reply_echo.is_empty():
		%email_content.text += "\n\n> " + r.effect.reply_echo


func _clear_replies() -> void:
	for c in %reply_list.get_children():
		c.queue_free()
	%reply_list.visible = false
	%profile_button.visible = false


## 待回复时锁住「下一封」：不表态就读不下去。
func _set_locked(locked: bool) -> void:
	%next_email.disabled = locked


func _on_profile_button_pressed() -> void:
	if _def == null or String(_def.about_employee).is_empty():
		return
	SignalBus.profile_focus_requested.emit(_def.about_employee)
