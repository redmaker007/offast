extends RefCounted
class_name level_runner

## 外层关卡图的解释器：现在是哪个天节点、第几天、经过了哪些天，下一天去哪。
##
## 不碰任何界面，也不管一天里面怎么玩（那是 round_manager 和以后的天内图解释器的事）。
## round_manager 每天结束问它一次 advance()，被开除时调 fire()。
##
## 规则见 docs/level_engine.md 第 2 节：
##   - 初始天是第 1 天，之后每进一个天节点 +1。
##   - 分化器按顺序判条件，第一个成立的走，都不成立走 else。
##   - 天数跳转器：set N → 下一个天节点就是第 N 天；add N → 下一个天节点是「本来的天数 + N」。

## 顺着分化器 / 跳转器最多走多少步。校验器保证走得到结局，但条件一直不成立的话
## 分化器之间还是可能绕圈，到上限就报错停下，不让游戏卡死。
const MAX_HOPS := 256

var doc: level_doc

## 校验出来的错误。不为空就不能开局。
var errors: Array[level_error] = []

## 当前所在的天节点 id。
var current := ""

## 现在是第几天。
var day := 0

## 经过的天节点流水账：[{"seq": 1, "node": "day_1", "day": 1}, ...]。
## 不能只拿天数当 key——有了时空跳跃，同一个天数可能出现两次。
var history: Array = []


## 读一份关卡并校验。读不到也返回一个 runner，原因放进 errors 里。
static func open(level_name: String) -> level_runner:
	var r := level_store.load_level(level_name)
	var runner := level_runner.new()
	if r.doc == null:
		runner.errors.append(level_error.new("LOAD_FAILED", {"detail": r.error}))
		return runner
	runner.set_doc(r.doc)
	return runner


func set_doc(d: level_doc) -> void:
	doc = d
	errors = level_validator.validate(d)


func is_valid() -> bool:
	return doc != null and errors.is_empty()


## 全部错误转成一段给人看的文字，一条一行。
func describe_errors() -> String:
	var lines: PackedStringArray = []
	for e in errors:
		lines.append(e.describe())
	return "\n".join(lines)


## 开新局：站到初始天上，第 1 天。
func start() -> void:
	history.clear()
	day = 0
	for n in doc.graph.of_type("day"):
		if str(n.props.get("role", "")) == "start":
			_enter(n.id, 1)
			return


## 今天结束，顺着出口走到下一个天节点。返回那个节点；出错（绕圈、断线）返回 null。
func advance() -> flow_node:
	var next_day := day + 1
	var at: flow_node = current_node()
	if at == null:
		return null
	var id := at.target("next")
	for hop in MAX_HOPS:
		var n := doc.graph.node(id)
		if n == null:
			push_error("关卡图从 %s 走到了不存在的节点「%s」" % [current, id])
			return null
		match n.type:
			"day":
				_enter(id, next_day)
				return n
			"brancher":
				id = _pick_branch(n)
			"jumper":
				var value := int(n.props.get("value", 0))
				if str(n.props.get("mode", "")) == "set":
					next_day = value
				else:
					next_day += value
				id = n.target("next")
			_:
				push_error("关卡图外层不认识的节点类型：%s（%s）" % [n.type, id])
				return null
	push_error("关卡图从 %s 出发走了 %d 步还没到下一天，分化器之间可能绕圈了" % [current, MAX_HOPS])
	return null


## 被开除：直接跳去背景设定里的那个结局天。返回那个节点。
func fire() -> flow_node:
	var id := str(doc.settings.get("fired_ending", ""))
	if doc.graph.has(id):
		_enter(id, day + 1)
	return current_node()


func current_node() -> flow_node:
	return doc.graph.node(current) if doc != null else null


func is_ending() -> bool:
	var n := current_node()
	return n != null and str(n.props.get("role", "")) == "ending"


## 结局天对应哪个结局（A / B / C / D / E）。
func ending_id() -> StringName:
	var n := current_node()
	return StringName(str(n.props.get("ending", ""))) if n != null else &""


## 当前天节点用的是哪一天的剧本（story_book.plan_for 的参数）。没写就跟天数走。
func plan_day() -> int:
	var n := current_node()
	if n == null:
		return day
	return int(n.props.get("plan", day))


## 命数（背景设定）。
func lives() -> int:
	return int(doc.settings.get("lives", 3)) if doc != null else 3


## 一共有几个要上班的天（结局天不算）。只用来显示「第 N 天 / 共 M 天」——
## 有分支的话每条路长短不一，这只是个参考值。
func total_days() -> int:
	if doc == null:
		return 0
	var count := 0
	for n in doc.graph.of_type("day"):
		if str(n.props.get("role", "")) != "ending":
			count += 1
	return count


func save_data() -> Dictionary:
	return {"current": current, "day": day, "history": history.duplicate(true)}


## 读档。old_day 是旧存档里只有的 current_day：那时还没有关卡图，
## 当时的天一定是线性的第 N 天，就按 day_N 找回去。
func load_data(d: Dictionary, old_day := 0) -> void:
	if d.has("current"):
		current = str(d["current"])
		day = int(d.get("day", 0))
		history = (d.get("history", []) as Array).duplicate(true)
		return
	day = old_day
	current = "day_%d" % old_day
	history = [{"seq": 1, "node": current, "day": day}]


func _enter(id: String, number: int) -> void:
	current = id
	day = number
	history.append({"seq": history.size() + 1, "node": id, "day": number})


func _pick_branch(n: flow_node) -> String:
	var cases := node_types.branch_cases(n)
	for i in cases.size():
		var cond := str(cases[i].get("if", "")) if cases[i] is Dictionary else ""
		if story_condition.eval(cond):
			return n.target(node_types.case_port(i))
	return n.target("else")
