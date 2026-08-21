extends Resource
class_name conversation_choice

## 选择题气泡上的一个选项。
##
## 单选：按下哪个就立刻按那个走，没有确认键。

## 按钮上显示的字。
@export_multiline var text: String = ""

## 选了之后跳到哪一段 dialogue（填对应 dialogue 的 id）。
## **留空 = 不跳**，接着走当前这段的下一条气泡；这段走完了就线性进下一段。
@export var goto: StringName = &""

## 这个选项要不要出现。留空 = 总是出现。
@export var condition: String = ""


## 现在该不该显示这个选项。
func available() -> bool:
	return story_condition.eval(condition)


## 选了之后的立场影响（数值 / 剧情开关）。留空 = 纯剧情选项。
## 和邮件回复、私信回复共用同一个类型，所以表态的规则只有一套。
@export var effect: story_effect


func jumps() -> bool:
	return not String(goto).is_empty()
