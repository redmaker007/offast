extends Node
class_name personnel_manager

## 人员调动 app 的后台：记玩家填的表，日终和 instruction_box 对答案。
##
## 邮件阅后即焚，所以这张表完全靠玩家的记忆填出来，是一天工作的唯一产出。
## 每个员工可以同时勾多个动作——加薪 + 升职是合法组合（见 f_instruction._apply），
## 所以 UI 上是四个独立开关而不是单选。
##
## **升职有每日名额**（`round_manager.promotions_per_day`，默认 1）：名额是唯一
## 一个「记得答案也不一定填得下」的地方，超额那一下会被挡掉并弹提示。

const ACTIONS := ["Fire", "Raise", "Promotion", "Reduction"]

## {员工名: {"Fire": bool, "Raise": bool, "Promotion": bool, "Reduction": bool}}
var assignments: Dictionary = {}

## 今天**不判对错**的行：员工自己申请加薪/升职的那些人，还有主角自己。
## 这些行照样出现在表上、照样进日志和剧情判定，但不进 correct/wrong。
var ungraded: Array = []

var save_id := "personnel_manager"


func _ready() -> void:
	add_to_group(SaveState.GROUP)


func save_data() -> Dictionary:
	# ungraded 也要存：读档回来要是忘了「这几行不判对错」，
	# 员工自己申请升职的那几行会突然开始扣血。
	return {"assignments": assignments, "ungraded": ungraded}


func load_data(d: Dictionary) -> void:
	assignments = d.get("assignments", {})
	ungraded = d.get("ungraded", [])


## 每天开工时清表。ungraded 是当天不判对错的人（round_manager 算好了递进来）。
func begin_day(ungraded_names: Array = []) -> void:
	assignments.clear()
	ungraded = ungraded_names.duplicate()


## 这一行算不算对错。
func is_graded(employee_name: String) -> bool:
	return not (employee_name in ungraded)


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


## app 里点一下切换一个动作。**返回有没有真的改动**——升职有每日名额，
## 名额用完时这一下会被挡掉（同时弹提示），UI 要据此把按钮弹回去。
func toggle(employee_name: String, action: String) -> bool:
	var row: Dictionary = row_for(employee_name)
	var turning_on := not bool(row.get(action, false))

	if turning_on and action == "Promotion" and not _promotion_slot_free():
		var limit: int = %round_manager.promotions_per_day
		var text: String = tr(%round_manager.promotion_limit_notice)
		if text.contains("%d"):
			text = text % limit
		SignalBus.notice_requested.emit(text)
		return false

	row[action] = turning_on
	return true


## 今天还有没有升职名额。-1 是不限制。
func _promotion_slot_free() -> bool:
	var limit: int = %round_manager.promotions_per_day
	if limit < 0:
		return true
	return promotions_used() < limit


## 今天已经给几个人填了升职。
func promotions_used() -> int:
	var used := 0
	for employee_name in assignments:
		if bool(assignments[employee_name].get("Promotion", false)):
			used += 1
	return used


## 日终判分。一个员工的四个动作全部吻合才算一条对。
##
## 除了分数还带回每一行的明细（rows）：日志要记玩家到底填了什么、命令是谁下的，
## 立场结算也要看「派系点名的人有没有照办」。判分和记账都要遍历同一份数据，
## 分开走两遍容易对不上，索性一次算完。
func grade() -> Dictionary:
	var truth: Dictionary = %instruction_box.get_all()
	var correct := 0
	var wrong := 0
	var rows: Array = []

	for employee_name in roster():
		var instruction = truth.get(employee_name)
		var expected := _expected_row(instruction)
		var actual: Dictionary = row_for(employee_name)
		var ok := true
		for action in ACTIONS:
			if bool(expected.get(action, false)) != bool(actual.get(action, false)):
				ok = false
				break
		# 不判分的行不进分母：员工自己申请升职，你给不给都不算错。
		if is_graded(employee_name):
			if ok:
				correct += 1
			else:
				wrong += 1
		rows.append({
			"employee": employee_name,
			"expected": expected.duplicate(),
			"actual": actual.duplicate(),
			# 谁下的令。随机信是空串（公司例行），只有派系命令信才进立场结算。
			"issuer": instruction.faction_key if instruction != null else &"",
			"complied": ok,
			"graded": is_graded(employee_name),
			# 一个动作都没填 = 明确的抗命（对派系命令而言），和「填错了」要分开。
			"blank": _is_blank(actual),
			"ordered": instruction != null,
		})

	var total := 0
	for employee_name in roster():
		if is_graded(employee_name):
			total += 1
	return {"correct": correct, "wrong": wrong, "total": total, "rows": rows}


func _is_blank(row: Dictionary) -> bool:
	for action in ACTIONS:
		if bool(row.get(action, false)):
			return false
	return true


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
