extends Resource
class_name story_effect

## 「选了这条会发生什么」的通用包。
##
## 邮件回复、内部私信回复、剧情对话选项、电话/便签桥段的选项——四处共用这一个类型，
## 所以立场怎么加、档案怎么解锁只有一套规则，加新的表态渠道不用再写一遍。
##
## 应用统一走 GameState.apply_effect()，这里只是纯数据。

@export_group("结局分")

## 四条结局线的增量，可以为负。
##   A 倒向班纳（A 派）  B 倒向罗德里克（B 派）
##   C 谁都不帮、维持制衡  D 把底层的人捧上去反杀
@export var a_delta: int = 0
@export var b_delta: int = 0
@export var c_delta: int = 0
@export var d_delta: int = 0

@export_group("剧情开关")

## 要打开的 flag（隐藏结局的条件、以及任何一次性剧情开关）。
@export var set_flags: Array[StringName] = []

@export_group("回显")

## 选完之后原地回显的一句话（邮件页显示「你回复了……」）。留空就不显示。
@export_multiline var reply_echo: String = ""


func is_empty() -> bool:
	return (a_delta == 0 and b_delta == 0 and c_delta == 0 and d_delta == 0
		and set_flags.is_empty())
