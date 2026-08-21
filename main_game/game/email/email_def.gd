extends Resource
class_name email_def

## 一封写死的剧情邮件。和随机信混在同一个收件箱里，玩家看不出区别，
## 但它有发件人身份、正文、以及（可选的）回复选项。
##
## 带 order 的剧情信照样进标准答案、照样判分扣命——派系头目下的命令
## 和公司例行公事在玩法上是一回事，区别只在「照不照办会被记立场」。

## 四个人事动作。Inspector 里是下拉框，NONE 表示这封信不含人事指令
## （比如欢迎信、打探信），不进标准答案。
enum Order { NONE, FIRE, RAISE, PROMOTION, REDUCTION }

## 这封信的唯一 id，用来记「已经回复过了」。同一局里别重名。
@export var id: StringName = &""

@export var sender_name: String = ""

## 谁的人。命令信照不照办会算进这一方的立场（见 round_manager 的结算）。
@export var sender_faction := faction.Id.NONE

@export var subject: String = ""

## 正文分段：没写条件的段总是显示，`?if ... ?end` 包起来的段只在条件成立时显示。
## 显示用 body_text()，别直接拼。
@export var body_blocks: Array[story_text_block] = []

## 整封信要不要发。留空 = 总是发。第三天班纳那两个版本就是靠它二选一。
@export var condition: String = ""

@export_group("人事指令")

## 这封信的指令算不算对错。**false = 进人事表但不判分**——
## 员工自己申请加薪/升职就是这种：他进了你的表，但填不填、怎么填都不扣血，
## 只影响剧情分。
@export var graded: bool = true

## 留 NONE 就是一封纯剧情信。
@export var order := Order.NONE

## 指令针对谁。填了 order 就必须填这个，否则这封信不会进标准答案。
## 特殊值 `*random` = 当天所有随机员工（round_manager 会展开成一人一条），
## 第二天班纳那封「把前面提到的员工全部 fire 掉」就是这么写的。
@export var target_employee: StringName = &""

## target_employee 填这个表示「当天所有随机员工」。
const ALL_RANDOM := &"*random"

## 发件人等级，和随机信同一套冲突规则：等级高的覆盖低的。
@export_range(0, 4) var sender_class: int = 0

@export_group("回复")

## 留空 = 这封信不能回，读完直接下一封。
@export var replies: Array[email_reply] = []

@export_group("关联")

## 这封信提到的员工，邮件页上「查档案」跳的就是他。留空则不显示这个按钮。
@export var about_employee: StringName = &""


const ORDER_NAMES := {
	Order.FIRE: "Fire",
	Order.RAISE: "Raise",
	Order.PROMOTION: "Promotion",
	Order.REDUCTION: "Reduction",
}


## 人事指令的字符串形式（和 que_generator / f_instruction 用的是同一套字面量）。
## 没有指令返回空串。
func order_name() -> String:
	return ORDER_NAMES.get(order, "")


func has_order() -> bool:
	return order != Order.NONE and not String(target_employee).is_empty()


func can_reply() -> bool:
	return not replies.is_empty()


## 现在这封信该不该发。
func should_send() -> bool:
	return story_condition.eval(condition)


## 当前条件下看得到的正文。
func body_text() -> String:
	var parts: Array[String] = []
	for block in body_blocks:
		if block != null and block.visible() and not block.text.is_empty():
			parts.append(block.text)
	return "\n".join(parts)


func targets_all_random() -> bool:
	return target_employee == ALL_RANDOM


## 生成一封可以扔进收件箱的运行时邮件。
## override_target 用来把 *random 展开成具体某个人。
## 只带 id，不带这个 Resource 本身——存档的 object_packer 会把 Resource 深拷贝
## 一份，而且这些定义是 .story 导入出来的内嵌子资源，没有独立路径。
## 要拿回定义去问 story_book.mail_def(id)。
func make_email(override_target := &"") -> email:
	var e := email.new()
	var target := override_target if not String(override_target).is_empty() else target_employee
	e.init_email(sender_name, order_name(), String(target), sender_class)
	e.id = id
	e.faction_key = faction.key(sender_faction)
	e.graded = graded
	return e
