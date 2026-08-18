extends Resource
class_name conversation

## 一整段剧情，由若干段 dialogue 组成。做成 .tres 存在 story/conversations/ 下，
## 在 Inspector 里点 + 加段、加气泡、拖头像、填文字，改文案不用碰代码。
##
## 播放顺序：从第一段开始线性往下走，走完一段接下一段，全部走完这段剧情就结束。
## 选项填了 goto 就跳到那一段，不填就继续线性。
##
## 播放状态不存在这里——这是纯数据，同一份 .tres 可以被播很多遍。
## 谁播到哪了归 story_page 管。

@export var dialogues: Array[dialogue] = []


func is_empty() -> bool:
	for d in dialogues:
		if d != null and not d.is_empty():
			return false
	return true


## 从哪一段开始播。
func first() -> dialogue:
	for d in dialogues:
		if d != null:
			return d
	return null


## 按 id 找一段，找不到返回 null（选项的 goto 写错了不至于崩，只是不跳）。
func find(id: StringName) -> dialogue:
	for d in dialogues:
		if d != null and d.id == id:
			return d
	return null


## 线性的下一段，没有了就返回 null（= 这段剧情播完了）。
func next_after(d: dialogue) -> dialogue:
	var i := dialogues.find(d)
	if i < 0:
		return null
	for j in range(i + 1, dialogues.size()):
		if dialogues[j] != null:
			return dialogues[j]
	return null
