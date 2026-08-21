extends Node

## 当天的标准答案：把**发出去的**邮件按员工累积成指令。
##
## 关键是听 send_email 而不是「玩家读了哪封」——挂钩到已读的话，
## 一封不读直接下班，答案库是空的，玩家的空表刚好全对，摆烂成了最优解。
## 邮件发出去公司就认为你该知道了，读不读是你自己的事。
##
## 冲突规则在 f_instruction.change_instruction 里——sender 等级高的覆盖低的，
## 同级则后来的覆盖先来的。邮件生成顺序和入队顺序一致，所以结果和逐封读一样。
##
## 整天都留着不清空，日终由 personnel_manager 拿去和玩家填的表对答案。
## 只在每天开工时清空。

var instruction_box = {}

var save_id := "instruction_box"


func _ready() -> void:
	add_to_group(SaveState.GROUP)
	SignalBus.send_email.connect(append_instruction)


func save_data() -> Dictionary:
	return {"instruction_box": instruction_box}


func load_data(d: Dictionary) -> void:
	instruction_box = d.get("instruction_box", {})


func append_instruction(e:email):
	# 剧情信可以不带人事指令（欢迎信、打探信），那种不进标准答案。
	if str(e.instruction).is_empty() or str(e.target_employee_name).is_empty():
		return
	# 员工自己申请加薪/升职（graded=no）也不进：他会出现在人事表上，
	# 但那一行怎么填都不算对错，只影响剧情分。
	if not e.graded:
		return
	var i = is_already_in_instruction_box(e)
	if i:
		i.change_instruction(e.instruction, e.sender_class, e.faction_key)
	else:
		i = f_instruction.new()
		i.init_instruction(e.instruction, e.target_employee_name, e.sender_class, e.faction_key)
		instruction_box[e.target_employee_name] = i


func is_already_in_instruction_box(e:email):
	if e.target_employee_name in instruction_box:
		return instruction_box[e.target_employee_name]
	return null


## 日终判分用，只读不清空。
func get_all() -> Dictionary:
	return instruction_box


## 每天开工前清空。
func clear_box() -> void:
	instruction_box.clear()
