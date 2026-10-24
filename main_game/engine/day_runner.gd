extends RefCounted
class_name day_runner

## 天内图的解释器：一天从 start 走到 day_end。
##
## 只管「走到哪了、下一步去哪」。条件分支和效果节点是纯状态，自己算；
## 剧情、视窗、发信、下班、结算这些要碰界面的步骤交给 host（游戏里是 round_manager）。
## 所以它可以拿一个假的 host 单独测。规则见 docs/level_engine.md 第 3 节。
##
## host 要提供：
##     run_step(node: flow_node) -> bool    执行一个强制元件。返回真 = 要等，等完调 step_done()
##     enter_free_play(node: flow_node)     进入自由环节
##
## 模式：
##     idle   还没开始 / 出错停了
##     chain  正在跑强制链（物件点了没反应，non_blocking 的除外）
##     free   停在自由环节，等玩家点物件或者到点
##     ended  走到 day_end 了

## 走到 day_end 时发出。
signal finished

const IDLE := "idle"
const CHAIN := "chain"
const FREE := "free"
const ENDED := "ended"

## 不锁其他物件的物件（non_blocking）是在别的强制链跑着的时候被点的，
## 它后面只能接瞬间做完的元件——要等的（剧情、结算）会和正在跑的那条链抢画面。
const INSTANT := ["window_bubble", "effect", "if", "send_mail", "show_ending"]

## 一口气最多走多少个瞬间节点。校验器保证强制链不绕圈，这只是防万一。
const MAX_STEPS := 512

var graph: flow_graph
var host: Object

var mode := IDLE

## 正在跑或正在等的节点。
var current := ""

## 最近进入的自由环节：可互动物件从它的 listen 上找，中途回菜单也退回这里。
var hub := ""

## 不能重复触发（repeat 为假）的可互动物件，今天触发过的。
var used := {}

## 强制链跑着的时候到点了：先记着，回到自由环节立刻下班。
var pending_time_up := false


func start(g: flow_graph, p_host: Object) -> void:
	graph = g
	host = p_host
	mode = IDLE
	current = ""
	hub = ""
	used = {}
	pending_time_up = false
	_go("start")


## host 那边等的东西完成了（剧情播完、结算确认……），接着往下走。
func step_done() -> void:
	if mode != CHAIN:
		return
	var n := graph.node(current)
	if n != null:
		_go(n.target("next"))


## 玩家点了一个物件。返回这次点击有没有被图接住。
func click(object_id: String) -> bool:
	if mode != FREE and mode != CHAIN:
		return false
	var fp := graph.node(hub)
	if fp == null:
		return false
	for id in fp.targets("listen"):
		var ia := graph.node(id)
		if ia == null or str(ia.props.get("object", "")) != object_id:
			continue
		var side := mode == CHAIN
		if side and not bool(ia.props.get("non_blocking", false)):
			return false
		if not story_condition.eval(str(ia.props.get("unlock", ""))):
			return false
		if not bool(ia.props.get("repeat", true)):
			if used.has(id):
				return false
			used[id] = true
		if side:
			_side_run(ia.target("next"))
		else:
			_go(ia.target("next"))
		return true
	return false


## 到点了。在自由环节就走 time_up；强制链跑着就先记下来。
func time_up() -> void:
	match mode:
		FREE:
			var fp := graph.node(hub)
			if fp != null:
				_go(fp.target("time_up"))
		CHAIN:
			pending_time_up = true


## 中途回菜单再读档：强制链不接着跑，退回链开始前的自由环节。
func abort_chain() -> void:
	if mode == CHAIN and graph.has(hub):
		mode = FREE
		current = hub


func save_data() -> Dictionary:
	return {"mode": mode, "current": current, "hub": hub, "used": used.keys(),
		"pending_time_up": pending_time_up}


## 读档。graph / host 先用 attach() 接上，再灌状态。
func load_data(d: Dictionary) -> void:
	mode = str(d.get("mode", IDLE))
	current = str(d.get("current", ""))
	hub = str(d.get("hub", ""))
	used = {}
	for id in d.get("used", []):
		used[str(id)] = true
	pending_time_up = bool(d.get("pending_time_up", false))


func attach(g: flow_graph, p_host: Object) -> void:
	graph = g
	host = p_host


func _go(id: String) -> void:
	for step in MAX_STEPS:
		var n := graph.node(id)
		if n == null:
			push_error("天内图走到了不存在的节点「%s」（从 %s 出发）" % [id, current])
			mode = IDLE
			return
		current = id
		match n.type:
			"start":
				id = n.target("next")
			"free_play":
				hub = id
				mode = FREE
				host.enter_free_play(n)
				if not pending_time_up:
					return
				pending_time_up = false
				id = n.target("time_up")
			"day_end":
				mode = ENDED
				finished.emit()
				return
			"if":
				id = _pick(n)
			"effect":
				mode = CHAIN
				apply_effect(n)
				id = n.target("next")
			_:
				mode = CHAIN
				if host.run_step(n):
					return
				# host 可能在 run_step 里就同步调了 step_done（比如剧情是空的，立刻播完），
				# 那时图已经往前走了，这里不能再走一遍。
				if current != id:
					return
				id = n.target("next")
	push_error("天内图一口气走了 %d 步还没停下，强制链可能绕圈了" % MAX_STEPS)
	mode = IDLE


## non_blocking 物件在别的强制链跑着时被点：只跑瞬间元件，碰到自由环节 / 天结束就停。
## 不改模式、不动 current——正在跑的那条链不受影响。
func _side_run(id: String) -> void:
	for step in MAX_STEPS:
		var n := graph.node(id)
		if n == null or n.type == "free_play" or n.type == "day_end":
			return
		if not n.type in INSTANT:
			push_warning("不锁其他物件的物件后面接了要等的元件「%s」（%s），强制链期间跳过" % [n.type, id])
			return
		match n.type:
			"if":
				id = _pick(n)
			"effect":
				apply_effect(n)
				id = n.target("next")
			_:
				host.run_step(n)
				id = n.target("next")


func _pick(n: flow_node) -> String:
	var cases := node_types.branch_cases(n)
	for i in cases.size():
		var cond := str(cases[i].get("if", "")) if cases[i] is Dictionary else ""
		if story_condition.eval(cond):
			return n.target(node_types.case_port(i))
	return n.target("else")


## 效果节点：条件成立才生效，改变量、开 flag。
static func apply_effect(n: flow_node) -> void:
	if not story_condition.eval(str(n.props.get("if", ""))):
		return
	var gs := story_condition._state()
	if gs == null:
		return
	var deltas = n.props.get("deltas", {})
	if deltas is Dictionary:
		for key in deltas:
			gs.add_var(StringName(str(key)), int(deltas[key]))
	for f in n.props.get("set_flags", []):
		gs.set_flag(StringName(str(f)))
