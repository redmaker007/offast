extends RefCounted
class_name email

## 收件箱里的一封信。随机信和剧情信都是这个类型——邮件页、instruction_box
## 一视同仁，剧情信只是多带了身份和回复选项。

var sender
var instruction
var target_employee_name
var sender_class:int

## ── 以下只有剧情信才有值 ──

## 剧情信的 id，用来记「已经回复过了」。随机信是空串。
var id: StringName = &""

## 对应 email_def 的 id。**存 id 不存 Resource**：存档的 object_packer 会把
## Resource 深拷贝一份；而且剧情信的定义现在是 .story 导入出来的内嵌子资源，
## 根本没有独立路径可存。要拿回定义去问 round_manager.mail_def(id)（关卡发信节点里找，找不到再问 story_book）。

## 发件人属于哪一派（faction.KEY_*）。随机信是空串。
var faction_key: StringName = &""

## 这封信的指令算不算对错。员工自己申请加薪/升职的信是 false：
## 人进表，但填不填都不扣血。随机信永远是 true。
var graded: bool = true


func init_email(_sender,_instruction,_target_employee_name,_sender_class):
	sender = _sender
	instruction = _instruction
	target_employee_name = _target_employee_name
	sender_class = _sender_class


func is_scripted() -> bool:
	return not String(id).is_empty()
