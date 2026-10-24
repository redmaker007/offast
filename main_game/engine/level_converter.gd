extends RefCounted
class_name level_converter

## 把现有的 .story 内容转成关卡图（第 1 阶段用）。
##
## 转出来的是一张**线性图**：第 1 天 → … → 第 N 天 → 结局分化器 → 各结局天。
## 分化器的条件照抄 world.story 的 [ending] 规则表，顺序不变、else 走兜底结局——
## 所以跑起来和原来 ending_director 自己查表的结果一模一样。
##
## 天内图这一阶段只放占位（开始 → 自由环节 → 结算 → 天结束），还不执行；
## 剧情、邮件、桥段仍然从 day_N.story 读（天节点的 props.plan 指向第几天的剧本）。
## 第 2 阶段再把它们转成真正的元件。
##
## 生成文件：godot --headless -s res://tools/convert_story_to_level.gd

const STORY_DIR := "res://story/zh"

## 原来 ending_director 的兜底结局，和被开除去的结局。
const FALLBACK_ENDING := "C"
const FIRED_ENDING := "E"
const ENDINGS := ["A", "B", "C", "D", "E"]

## 房间里的可互动物件（main_scene 里 Control 下那 8 个 *_control）。
## 第 3 阶段房间数据化之后，这份表会带上位置、贴图和热区。
const ROOM_OBJECTS := {
	"door": {"zh": "门", "en": "Door"},
	"light": {"zh": "灯", "en": "Light"},
	"electricbox": {"zh": "电箱", "en": "Electric box"},
	"laptop": {"zh": "电脑", "en": "Laptop"},
	"notes": {"zh": "便签", "en": "Notes"},
	"caller": {"zh": "电话", "en": "Phone"},
	"table": {"zh": "桌子", "en": "Table"},
	"calendar": {"zh": "日历", "en": "Calendar"},
}

const COLUMN := 260.0


## 按 res://story/zh 现有的内容转。
static func from_story_dir(dir := STORY_DIR) -> level_doc:
	var world := load(dir + "/world.story") as world_book
	var day_count := 0
	while ResourceLoader.exists("%s/days/day_%d.story" % [dir, day_count + 1]):
		day_count += 1
	return from_world(world, day_count)


static func from_world(world: world_book, day_count: int) -> level_doc:
	var doc := level_doc.create()
	doc.settings["fired_ending"] = _ending_id(FIRED_ENDING)
	var objects: Array = []
	for id in ROOM_OBJECTS:
		objects.append({"id": id, "name": ROOM_OBJECTS[id]})
	doc.world["objects"] = objects

	var g := doc.graph
	for i in range(1, day_count + 1):
		var n := g.add(flow_node.new("day_%d" % i, "day"))
		n.pos = Vector2((i - 1) * COLUMN, 0)
		n.props = {
			"role": "start" if i == 1 else "normal",
			"name": {"zh": "第 %d 天" % i, "en": "Day %d" % i},
			"plan": i,
		}
		n.body = _work_day_body()
		if i < day_count:
			n.link("next", "day_%d" % (i + 1))

	var br := g.add(flow_node.new("ending_branch", "brancher"))
	br.pos = Vector2(day_count * COLUMN, 0)
	var cases: Array = []
	var rules: Array = world.ending_rules if world != null else []
	for i in rules.size():
		cases.append({"if": rules[i].condition})
		br.link(node_types.case_port(i), _ending_id(String(rules[i].ending)))
	br.props["cases"] = cases
	br.link("else", _ending_id(FALLBACK_ENDING))
	if day_count > 0:
		g.node("day_%d" % day_count).link("next", br.id)

	for i in ENDINGS.size():
		var e: String = ENDINGS[i]
		var n := g.add(flow_node.new(_ending_id(e), "day"))
		n.pos = Vector2((day_count + 1) * COLUMN, i * 140.0)
		n.props = {"role": "ending", "name": {"zh": "结局 %s" % e, "en": "Ending %s" % e}, "ending": e}
		n.body = _ending_body()
	return doc


static func _ending_id(e: String) -> String:
	return "end_" + e


## 上班天的占位：开始 → 自由环节 ─到点→ 结算 → 天结束。
static func _work_day_body() -> flow_graph:
	var g := flow_graph.new()
	_place(g, "start", "start", 0).link("next", "free_play")
	_place(g, "free_play", "free_play", 1).link("time_up", "result")
	_place(g, "result", "show_result", 2).link("next", "end")
	_place(g, "end", "day_end", 3)
	return g


## 结局天的占位：开始 → 人事日志 → 天结束。（结局对话和结局卡第 2 阶段再接成元件。）
static func _ending_body() -> flow_graph:
	var g := flow_graph.new()
	_place(g, "start", "start", 0).link("next", "log")
	_place(g, "log", "show_log", 1).link("next", "end")
	_place(g, "end", "day_end", 2)
	return g


static func _place(g: flow_graph, id: String, type: String, column: int) -> flow_node:
	var n := g.add(flow_node.new(id, type))
	n.pos = Vector2(column * 220.0, 0)
	return n
