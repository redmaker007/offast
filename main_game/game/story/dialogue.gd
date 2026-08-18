extends Resource
class_name dialogue

## 一段对话：一串按顺序播的气泡。
##
## 分段是为了给选项留跳转目标——选项填了 goto，就跳到 id 对得上的那一段。
## 不用分支的话整个 conversation 放一段就行，会从头线性播到尾。

## 这一段的名字，选项的 goto 填的就是它。同一个 conversation 里别重名。
@export var id: StringName = &"start"

@export var bubbles: Array[conversation_bubble] = []


func is_empty() -> bool:
	return bubbles.is_empty()


## 第 i 条气泡，越界返回 null。
func bubble_at(i: int) -> conversation_bubble:
	if i < 0 or i >= bubbles.size():
		return null
	return bubbles[i]
