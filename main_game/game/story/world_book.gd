extends Resource
class_name world_book

## 全局设定：系统账户 + 员工档案 + 电话联系人。由 story/world.story 导入生成，别手改。
##
## 和 day_plan 分开：账户和档案不属于某一天，它们整局都在。

@export var accounts: Array[account] = []
@export var profiles: Array[employee_profile] = []

## 能打电话的人。号码每局随机，见 contact。
@export var contacts: Array[contact] = []

## 结局判定规则，按顺序判，第一条成立的算数。都不成立走兜底结局 C。
@export var ending_rules: Array[ending_rule] = []

## 五个结局的文案（A/B/C/D/E）。和剧情放在一起，换语言时一起换。
@export var endings: Array[ending_def] = []

## 随机员工的名字池。**留空就用 que_generator 里那份内置英文名单**，
## 中文局要的是另一套名字（不是把 Jack 翻译成杰克），所以跟着内容文件走。
@export var random_names: Array[StringName] = []


func ending_text(id: StringName) -> ending_def:
	for e in endings:
		if e != null and e.ending_id == id:
			return e
	return null
