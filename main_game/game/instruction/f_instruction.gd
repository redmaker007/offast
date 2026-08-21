extends RefCounted
class_name f_instruction

var has_fire: bool = false
var has_raise: bool = false
var has_promotion: bool = false
var has_reduction: bool = false
var target_employee_name: String = ""
var sender_class: int = 0

## 最后一条生效指令是谁下的（faction.KEY_*）。随机信是空串。
## 日终结算「玩家到底照不照办」时按这个记立场，所以要跟着覆盖规则一起走：
## 被高等级发件人盖掉的指令，派系也跟着换成新发件人的。
var faction_key: StringName = &""

func init_instruction(_instruction, _target_employee_name, _sender_class, _faction_key := &""):
	target_employee_name = _target_employee_name
	sender_class = _sender_class
	faction_key = _faction_key
	_apply(_instruction)

func change_instruction(_instruction, _sender_class, _faction_key := &""):
	if _sender_class >= sender_class:
		sender_class = _sender_class
		faction_key = _faction_key
		_apply(_instruction)

func _apply(_instruction):
	match _instruction:
		"Fire":
			has_fire = true
			has_raise = false
			has_promotion = false
			has_reduction = false
		"Raise":
			has_fire = false
			has_raise = true
			has_reduction = false
		"Promotion":
			has_fire = false
			has_promotion = true
			has_reduction = false
		"Reduction":
			has_fire = false
			has_raise = false
			has_promotion = false
			has_reduction = true

func get_final_state() -> Dictionary:
	return {
		"Fire": has_fire,
		"Raise": has_raise,
		"Promotion": has_promotion,
		"Reduction": has_reduction
	}
