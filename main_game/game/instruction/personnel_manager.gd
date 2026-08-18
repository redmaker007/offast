extends Node
class_name personnel_manager

## 人员调动 app 的后台：记玩家填的表，日终和 instruction_box 对答案。
##
## 邮件阅后即焚，所以这张表完全靠玩家的记忆填出来，是一天工作的唯一产出。
## 每个员工可以同时勾多个动作——加薪 + 升职是合法组合（见 f_instruction._apply），
## 所以 UI 上是四个独立开关而不是单选。

const ACTIONS := ["Fire", "Raise", "Promotion", "Reduction"]

## {员工名: {"Fire": bool, "Raise": bool, "Promotion": bool, "Reduction": bool}}
var assignments: Dictionary = {}

var save_id := "personnel_manager"


func _ready() -> void:
	add_to_group(SaveState.GROUP)


func save_data() -> Dictionary:
	return {"assignments": assignments}


func load_data(d: Dictionary) -> void:
	assignments = d.get("assignments", {})


## 每天开工时清表。
func begin_day() -> void:
	assignments.clear()


## app 要显示哪些人。只列当天被点名的员工——这不泄露答案，
## 难点在于记住每个人要做什么，而不是猜谁被提到了。
func roster() -> Array:
	return %round_manager.current_round_employee_name_list


func row_for(employee_name: String) -> Dictionary:
	if not assignments.has(employee_name):
		assignments[employee_name] = _empty_row()
	return assignments[employee_name]


func is_set(employee_name: String, action: String) -> bool:
	return bool(row_for(employee_name).get(action, false))


## app 里点一下切换一个动作。
func toggle(employee_name: String, action: String) -> void:
	var row: Dictionary = row_for(employee_name)
	row[action] = not bool(row.get(action, false))


## 日终判分。一个员工的四个动作全部吻合才算一条对。
func grade() -> Dictionary:
	var truth: Dictionary = %instruction_box.get_all()
	var correct := 0
	var wrong := 0

	for employee_name in roster():
		var expected := _expected_row(truth.get(employee_name))
		var actual: Dictionary = row_for(employee_name)
		var ok := true
		for action in ACTIONS:
			if bool(expected.get(action, false)) != bool(actual.get(action, false)):
				ok = false
				break
		if ok:
			correct += 1
		else:
			wrong += 1

	return {"correct": correct, "wrong": wrong, "total": roster().size()}


func _empty_row() -> Dictionary:
	var row := {}
	for action in ACTIONS:
		row[action] = false
	return row


## 没收到任何指令的员工，正确答案就是「什么都不做」。
func _expected_row(instruction) -> Dictionary:
	if instruction == null:
		return _empty_row()
	return instruction.get_final_state()
