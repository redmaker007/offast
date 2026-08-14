extends RefCounted
class_name f_instruction

var has_fire: bool = false
var has_raise: bool = false
var has_promotion: bool = false
var has_reduction: bool = false
var target_employee_name: String = ""
var sender_class: int = 0

func init_instruction(_instruction, _target_employee_name, _sender_class):
	target_employee_name = _target_employee_name
	sender_class = _sender_class
	_apply(_instruction)

func change_instruction(_instruction, _sender_class):
	if _sender_class >= sender_class:
		sender_class = _sender_class
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
