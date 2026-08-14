extends RefCounted
class_name email

var sender
var instruction
var target_employee_name
var sender_class:int

func init_email(_sender,_instruction,_target_employee_name,_sender_class):
	sender = _sender
	instruction = _instruction
	target_employee_name = _target_employee_name
	sender_class = _sender_class
