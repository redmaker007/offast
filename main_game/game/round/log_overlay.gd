extends PanelContainer

## 人事调动日志：第 5 天结局之前，把五天里玩家做过的每一个决定摊开。
##
## 这一层不判断对错，只是把 GameState.personnel_log 原样念出来——
## 「谁下的令、你到底做了什么」，让玩家自己认出他这五天站到了哪一边。




func _ready() -> void:
	visible = false
	SignalBus.log_review_requested.connect(_on_review_requested)


func _on_review_requested() -> void:
	_rebuild()
	visible = true


func _rebuild() -> void:
	var list: VBoxContainer = %log_list
	for c in list.get_children():
		c.queue_free()

	if GameState.personnel_log.is_empty():
		var empty := Label.new()
		empty.text = tr("UI_LOG_EMPTY")
		list.add_child(empty)
		return

	for row in GameState.personnel_log:
		var line := Label.new()
		line.text = tr("UI_LOG_ROW") % [
			int(row.get("day", 0)),
			_display_name(str(row.get("employee", ""))),
			_actions_text(row.get("actual", {})),
			faction.display(row.get("issuer", &"")),
		]
		list.add_child(line)


## 日志上显示的名字：和人事表一样，标识 → 当前语言的显示名。
func _display_name(employee_name: String) -> String:
	if employee_name == String(GameState.SELF):
		return tr("UI_SELF_ROW")
	var p: employee_profile = %story_book.profile(StringName(employee_name))
	return p.label() if p != null else employee_name


## 玩家实际填的动作。记的是玩家做的，不是公司要求的——日志是他的履历，不是答案。
func _actions_text(actual: Dictionary) -> String:
	var picked: Array[String] = []
	for action in personnel_manager.ACTIONS:
		if bool(actual.get(action, false)):
			picked.append(action)
	if picked.is_empty():
		return tr("UI_LOG_NOTHING")
	return " + ".join(picked)


func _on_continue_pressed() -> void:
	visible = false
	SignalBus.log_review_finished.emit()
