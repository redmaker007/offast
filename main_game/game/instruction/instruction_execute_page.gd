extends PanelContainer

## 人事 app：笔记本的第二个 app。玩家凭记忆给当天点名的员工填调动动作。
##
## 四个动作是四个独立开关，不是单选——加薪 + 升职是合法组合
## （见 f_instruction._apply）。表格改动即时写进 personnel_manager，
## 没有单独的提交键：下班就是提交。
##
## 行是按当天名单动态生成的，所以场景里只放一个空的 %personnel_list 容器。

const ACTION_LABELS := {
	"Promotion": "↑",
	"Reduction": "↓",
	"Raise": "$",
	"Fire": "✕",
}


func _ready() -> void:
	SignalBus.round_state_change.connect(_on_round_state_change)
	SignalBus.game_restored.connect(_rebuild)


func _on_round_state_change(rs) -> void:
	# 每天开工重新铺一次表，名单换人了行也要跟着换。
	if rs == RoundState.Round_State.GAME:
		_rebuild()


func _rebuild() -> void:
	var list: VBoxContainer = %personnel_list
	for c in list.get_children():
		c.queue_free()

	for employee_name in %personnel_manager.roster():
		list.add_child(_make_row(employee_name))


func _make_row(employee_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	# 主角自己那一行在表上叫「你自己」——第四、五天要能给自己批 promotion。
	label.text = _display_name(employee_name)
	label.custom_minimum_size = Vector2(140, 0)
	row.add_child(label)

	for action in %personnel_manager.ACTIONS:
		var b := Button.new()
		b.text = ACTION_LABELS.get(action, action)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(56, 44)
		# 读档回来时要把已经填过的状态摆回去。
		b.button_pressed = %personnel_manager.is_set(employee_name, action)
		b.toggled.connect(_on_action_toggled.bind(employee_name, action))
		row.add_child(b)

	return row


## 表上显示的名字：主角自己那一行叫「你自己」，剧情角色用档案里的显示名，
## 随机员工就是名字本身。**存进数据层的一律是标识**，翻译只影响这一层显示。
func _display_name(employee_name: String) -> String:
	if employee_name == String(GameState.SELF):
		return tr("UI_SELF_ROW")
	var p: employee_profile = %story_book.profile(StringName(employee_name))
	return p.label() if p != null else employee_name


func _on_action_toggled(pressed: bool, employee_name: String, action: String) -> void:
	# 上面摆初始状态时也会触发 toggled，值没变就别再翻一次。
	if %personnel_manager.is_set(employee_name, action) == pressed:
		return
	if %personnel_manager.toggle(employee_name, action):
		return
	# 被挡掉了（升职名额用完）：数据层没动，按钮得弹回去，
	# 否则表上看着是勾着的，判分时却按没勾算。
	_sync_row(employee_name, action)


## 把某个格子的按钮状态摆回和数据层一致。
func _sync_row(employee_name: String, action: String) -> void:
	for row in %personnel_list.get_children():
		var label := row.get_child(0) as Label
		if label == null or label.text != employee_name:
			continue
		var index: int = %personnel_manager.ACTIONS.find(action)
		if index < 0:
			return
		var button := row.get_child(1 + index) as Button
		if button != null:
			button.set_pressed_no_signal(%personnel_manager.is_set(employee_name, action))
		return
