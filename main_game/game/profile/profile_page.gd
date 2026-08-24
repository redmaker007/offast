extends PanelContainer

## 档案页：笔记本的第三个 app。
##
## 能查到谁只看一件事：**当前登录账户的 clearance >= 那份档案的 clearance**。
## 查不到的人**根本不出现在名单里**——不是灰着显示——「这个号查不到这个人」
## 本身就是信息，灰着摆在那反而是在勾玩家。
##
## 所以「解锁更多情报」的动作不在这一页，而在登录页：拿到别人的号，
## 回来一登，名单就变长了。

var _selected: StringName = &""


func _ready() -> void:
	SignalBus.profile_focus_requested.connect(_on_focus_requested)
	SignalBus.login_succeeded.connect(_on_login_changed)
	SignalBus.logged_out.connect(_on_login_changed)
	SignalBus.game_restored.connect(_rebuild)
	# 换语言：名单和正文都跟着语言走。
	SignalBus.story_content_reloaded.connect(func(_loc: String) -> void: _rebuild())
	SignalBus.round_state_change.connect(_on_round_state_change)
	_rebuild()


func _on_round_state_change(_rs) -> void:
	_rebuild()


func _on_login_changed(_a = null) -> void:
	# 换了号，能查到的人跟着变。
	_rebuild()


## 邮件里点「查档案」跳过来：先选中人，再由 laptop_page 翻页。
## 权限不够的话这一页会明说查不到，而不是假装没这个人存在——
## 邮件里都提到他了，装看不见反而怪。
func _on_focus_requested(employee_name: StringName) -> void:
	_selected = employee_name
	_show_detail()


func _rebuild() -> void:
	var list: VBoxContainer = %profile_list
	for c in list.get_children():
		c.queue_free()

	var visible_profiles: Array = %story_book.profiles_for(GameState.clearance())
	for p in visible_profiles:
		var b := Button.new()
		b.text = p.label()
		b.custom_minimum_size = Vector2(180, 40)
		b.theme_type_variation = &"LongButton"
		b.pressed.connect(_on_name_pressed.bind(p.employee_name))
		list.add_child(b)

	if not _is_visible(_selected) and not visible_profiles.is_empty():
		_selected = visible_profiles[0].employee_name
	_show_detail()


func _on_name_pressed(employee_name: StringName) -> void:
	_selected = employee_name
	_show_detail()


## 这个人现在查得到吗。
func _is_visible(employee_name: StringName) -> bool:
	var p: employee_profile = %story_book.profile(employee_name)
	return p != null and p.clearance <= GameState.clearance()


func _show_detail() -> void:
	var p: employee_profile = %story_book.profile(_selected)
	if p == null:
		_show_blank(tr("UI_PICK_A_NAME") if String(_selected).is_empty() else tr("UI_NO_RECORD"))
		return
	if p.clearance > GameState.clearance():
		# 档案存在，但这个号看不到——邮件里提到过的人会走到这里。
		_show_blank(tr("UI_NO_RECORD"))
		return

	%profile_name.text = p.label()
	%profile_meta.text = "%s · %s · %s" % [
		p.position if not p.position.is_empty() else "—",
		p.department if not p.department.is_empty() else "—",
		faction.display(faction.key(p.employee_faction)),
	]
	%profile_avatar.texture = p.avatar
	# 档案里也可能写着某人的电话号码。
	%profile_body.text = story_text.resolve(p.body)


func _show_blank(message: String) -> void:
	%profile_name.text = message
	%profile_meta.text = ""
	%profile_body.text = ""
	%profile_avatar.texture = null
