extends RefCounted
class_name node_types

## 节点类型注册表：每种类型有哪些出口、哪些必须接、能接到什么类型。
## 校验器、以后的编辑器画布、解释器都从这里查，加新元件只改这一处。
##
## 出口描述是一个字典：
##     {"name": "next", "multi": false, "required": true, "targets": ["day", ...]}
## targets 为空表示什么类型都能接。

const OUTER := "outer"
const INNER := "inner"

## 外层能互相接的类型。
const OUTER_FLOW := ["day", "brancher", "jumper"]

## 天节点的 role。
const ROLES := ["start", "normal", "ending"]

## 天数跳转器的 mode。
const JUMP_MODES := ["set", "add"]

## 强制元件：播放期间锁交互，一个接一个跑，最后必须收在自由环节或 day_end 上。
const FORCED := ["story_bubble", "window_bubble", "send_mail", "effect", "show_result", "show_log"]

## 强制链里的一步能接到的地方。可互动物件不在里面：它只能挂在自由环节的 listen 上。
const CHAIN_TARGETS := ["story_bubble", "window_bubble", "send_mail", "effect",
	"show_result", "show_log", "free_play", "day_end"]

const INNER_TYPES := ["start", "free_play", "interactable", "story_bubble", "window_bubble",
	"send_mail", "effect", "show_result", "show_log", "day_end"]


static func is_known(kind: String, type: String) -> bool:
	if kind == OUTER:
		return type in OUTER_FLOW
	return type in INNER_TYPES


## 这个节点有哪些出口。有的类型出口数量跟着 props 变（分化器一个条件一个出口）。
static func ports(kind: String, n: flow_node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if kind == OUTER:
		match n.type:
			"day":
				if str(n.props.get("role", "")) != "ending":
					result.append(_port("next", OUTER_FLOW))
			"brancher":
				for i in branch_cases(n).size():
					result.append(_port(case_port(i), OUTER_FLOW))
				result.append(_port("else", OUTER_FLOW))
			"jumper":
				result.append(_port("next", OUTER_FLOW))
		return result

	match n.type:
		"start", "interactable":
			result.append(_port("next", CHAIN_TARGETS))
		"free_play":
			result.append(_port("listen", ["interactable"], true, false))
			result.append(_port("time_up", CHAIN_TARGETS))
		_:
			if n.type in FORCED:
				result.append(_port("next", CHAIN_TARGETS))
	return result


## 分化器第 i 个条件（0 起）对应的出口名：case_1、case_2……
static func case_port(i: int) -> String:
	return "case_%d" % (i + 1)


## 分化器的条件列表，每项是 {"if": "条件"}。
static func branch_cases(n: flow_node) -> Array:
	var cases = n.props.get("cases", [])
	return cases if cases is Array else []


static func _port(name: String, targets: Array, multi := false, required := true) -> Dictionary:
	return {"name": name, "multi": multi, "required": required, "targets": targets}
