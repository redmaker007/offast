extends Resource
class_name conversation_bubble

## 一条对话气泡。传统 RPG 对话框那一条。
##
## 气泡分两边：
##   THEIRS（对方，头像在右）—— 系统旁白、NPC、电脑播报
##   MINE  （我方，头像在左）—— 玩家自己说的话
##
## 再分两种推进方式，看 choices 填没填：
##   choices 为空 —— 普通气泡，读完按 Next 就切
##   choices 非空 —— 选择题，必须按下某个选项才切
##
## 朝向（头像左右、气泡尖角方向）由 bubble_view 决定怎么摆，数据这边只记是谁说的。


## 谁说的。
enum Side {
	THEIRS,  ## 对方：旁白 / NPC / 电脑
	MINE,    ## 我方：玩家
}


@export var side := Side.THEIRS

## 这条气泡的头像。留空就用 bubble_view 上配的默认头像。
@export var avatar: Texture2D

@export_multiline var text: String = ""

## 逐字机还没打完时按 Next 能不能一次刷出全文。
##
## **重要剧情设 false**：玩家狂点也跳不过去，必须等文字自己走完。
## 注意这管的是「能不能提前」，不是「能不能跳过这条」——文字出完了照样按 Next 进下一条。
@export var can_skip: bool = true

## 选项。**留空就是普通气泡**，非空就变成选择题。
@export var choices: Array[conversation_choice] = []

## 这一条要不要播。留空 = 总是播；写了条件（`?if ...` 包起来的那些行）
## 就只在成立时播，不成立整条跳过。语法见 story_condition。
@export var condition: String = ""


## 现在该不该播这一条。
func visible() -> bool:
	return story_condition.eval(condition)


## 是不是选择题气泡。
func is_choice() -> bool:
	return not choices.is_empty()
