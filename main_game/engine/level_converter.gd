extends RefCounted
class_name level_converter

## 把现有的 .story 内容转成关卡图。
##
## 外层是一张**线性图**：第 1 天 → … → 第 N 天 → 结局分化器 → 各结局天。
## 分化器的条件照抄 world.story 的 [ending] 规则表，顺序不变、else 走兜底结局——
## 所以跑起来和原来 ending_director 自己查表的结果一模一样。
##
## 天内图是**显式连线**的完整流程（第 2 阶段起），一天长这样：
##
##   start → 开场剧情 → 发信 → 自由环节 ─listen→ 电脑 → 视窗(电脑) → 回自由环节
##                                   ├listen→ 便签(不锁其他物件) → 视窗(便签) → 回
##                                   ├listen→ 日历 → 视窗(日历) → 回
##                                   ├listen→ 电话 → if 今天的来电还没接 → 记下 → 来电剧情 → 回
##                                   │                └else → 视窗(拨号盘) → 回
##                                   ├listen→ 电箱 → 电箱桥段 → 回（只有当天有桥段才有这个物件）
##                                   ├listen→ 门 → if 收件箱清空 → 下班结算链
##                                   │             └else → 「活还没干完」 → 回
##                                   └time_up → 下班结算链
##   下班结算链：下班（判分、记日志、扣命）→ 当天的 [score] 效果… → 结算画面 → 天结束
##
## 剧情和邮件的**文字**直接存进节点（第 2c 步起），每种语言一份：
## 转换器读 res://story/<语言>/days/day_N.story 的原文，按块切开，原样塞进去。
## 结构（有没有电箱、[score] 有几条、名单）按中文那份定。
## 结局对话和结局卡文字属于世界设定，还在 world.story（等世界表迁移）。
##
## 生成文件：godot --headless -s res://tools/convert_story_to_level.gd

const STORY_ROOT := "res://story"
const STORY_DIR := "res://story/zh"

## 结构按哪种语言定（各语言的块应该一一对应）。
const BASE_LOCALE := "zh"
const LOCALES := ["zh", "en"]

## 跟在剧情 / 桥段后面的分支块，切块时并进前一段对话里。
const DIALOGUE_OWNERS := ["story", "caller", "electricbox", "window"]
const UI_CSV := "res://locale/ui.csv"

## 原来 ending_director 的兜底结局，和被开除去的结局。
const FALLBACK_ENDING := "C"
const FIRED_ENDING := "E"
const ENDINGS := ["A", "B", "C", "D", "E"]

## 被开除那条路单独一个结局天：不摊日志、不播结局对话，直接出结局卡。
## （同样是 E，从规则表走过来的要先看日志，所以不能共用一个节点。）
const FIRED_NODE := "end_E_fired"

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
const ROW := 120.0


## 按 res://story 现有的内容转：每天一份「语言 -> 原文」。
static func from_story_dir(root := STORY_ROOT) -> level_doc:
	var world := load("%s/%s/world.story" % [root, BASE_LOCALE]) as world_book
	var days: Array[Dictionary] = []
	while true:
		var texts := {}
		for loc in LOCALES:
			var path := "%s/%s/days/day_%d.story" % [root, loc, days.size() + 1]
			if FileAccess.file_exists(path):
				texts[loc] = FileAccess.get_file_as_string(path)
		if not texts.has(BASE_LOCALE):
			break
		days.append(texts)
	return from_world(world, days)


## days：每天一份 {"zh": 原文, "en": 原文}。
static func from_world(world: world_book, days: Array[Dictionary]) -> level_doc:
	var doc := level_doc.create()
	doc.settings["fired_ending"] = FIRED_NODE
	doc.world["objects"] = room_objects()

	var g := doc.graph
	var day_count := days.size()
	for i in range(1, day_count + 1):
		var n := g.add(flow_node.new("day_%d" % i, "day"))
		n.pos = Vector2((i - 1) * COLUMN, 0)
		n.props = {
			"role": "start" if i == 1 else "normal",
			"name": {"zh": "第 %d 天" % i, "en": "Day %d" % i},
			"plan": i,
		}
		n.body = work_day_body(i, days[i - 1])
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
		n.body = ending_body(e)

	var fired := g.add(flow_node.new(FIRED_NODE, "day"))
	fired.pos = Vector2((day_count + 1) * COLUMN, ENDINGS.size() * 140.0)
	fired.props = {"role": "ending", "name": {"zh": "被开除", "en": "Fired"}, "ending": FIRED_ENDING}
	fired.body = fired_body(FIRED_ENDING)
	return doc


## 世界表里的房间物件那一栏。
static func room_objects() -> Array:
	var objects: Array = []
	for id in ROOM_OBJECTS:
		objects.append({"id": id, "name": ROOM_OBJECTS[id]})
	return objects


static func _ending_id(e: String) -> String:
	return "end_" + e


## 第 day 天的完整天内图，见文件头的图。texts 是 {"zh": 原文, "en": 原文}；
## 空的 {} 也能转（一天什么剧情都没有，只有物件和下班）。
static func work_day_body(day: int, texts: Dictionary) -> flow_graph:
	var plan: day_plan = null
	if texts.has(BASE_LOCALE):
		var parsed := story_parser.parse(texts[BASE_LOCALE], "day_%d.story" % day)
		if parsed.ok():
			plan = parsed.day
		else:
			push_error("第 %d 天的剧本解析失败：%s" % [day, parsed.errors])
	var blocks := {}
	for loc in texts:
		blocks[loc] = split_blocks(texts[loc])

	var g := flow_graph.new()
	var b := _Builder.new(g)

	b.put("start", "start", 0, 0).link("next", "opening")
	b.put("opening", "story_bubble", 1, 0,
		{"layer": "story", "script": _block_text(blocks, "story")}).link("next", "mail")
	b.put("mail", "send_mail", 2, 0, _mail_props(plan, blocks)).link("next", "free_play")
	var fp := b.put("free_play", "free_play", 3, 0)

	# 只有自带弹窗、点了就开的物件：物件 → 视窗 → 回自由环节。
	var row := 1
	for obj in ["laptop", "notes", "calendar"]:
		var ia := b.listen(fp, obj, 4, row, {"non_blocking": obj == "notes"})
		b.put(obj + "_window", "window_bubble", 5, row, {"object": obj, "page": ""}).link("next", "free_play")
		ia.link("next", obj + "_window")
		row += 1

	# 电话：今天的来电没接过就先播来电，接过了（或今天没有来电）就是拨号盘。
	var phone := b.listen(fp, "caller", 4, row)
	b.put("caller_window", "window_bubble", 6, row + 1, {"object": "caller", "page": ""}).link("next", "free_play")
	if _has_event(plan, &"caller"):
		var flag := event_flag(&"caller", day)
		var check := b.put("caller_check", "if", 5, row, {"cases": [{"if": "not flag:" + flag}]})
		phone.link("next", check.id)
		check.link("case_1", "caller_mark")
		check.link("else", "caller_window")
		b.put("caller_mark", "effect", 6, row, {"set_flags": [flag]}).link("next", "caller_event")
		b.put("caller_event", "story_bubble", 7, row,
			{"layer": "event", "script": _block_text(blocks, "caller")}).link("next", "free_play")
	else:
		phone.link("next", "caller_window")
	row += 2

	# 电箱：当天没有桥段就不挂这个物件（点了没反应，和原来一样）。
	if _has_event(plan, &"electricbox"):
		var box := b.listen(fp, "electricbox", 4, row, {"repeat": plan.repeats(&"electricbox")})
		b.put("electricbox_event", "story_bubble", 6, row,
			{"layer": "event", "script": _block_text(blocks, "electricbox")}).link("next", "free_play")
		if plan.repeats(&"electricbox"):
			box.link("next", "electricbox_event")
		else:
			var flag := event_flag(&"electricbox", day)
			var check := b.put("electricbox_check", "if", 5, row, {"cases": [{"if": "not flag:" + flag}]})
			box.link("next", check.id)
			check.link("case_1", "electricbox_mark")
			check.link("else", "free_play")
			b.put("electricbox_mark", "effect", 5, row + 1, {"set_flags": [flag]}).link("next", "electricbox_event")
		row += 2

	# 门：瞬发判定，收件箱清空才下班。
	var door := b.listen(fp, "door", 4, row)
	var door_check := b.put("door_check", "if", 5, row, {"cases": [{"if": story_condition.INBOX_EMPTY}]})
	door.link("next", door_check.id)
	door_check.link("case_1", "clock_out")
	door_check.link("else", "unfinished")
	b.put("unfinished", "story_bubble", 6, row,
		{"layer": "notice", "script": _ui_text("UI_UNFINISHED")}).link("next", "free_play")

	# 到点和点门共用一条下班结算链。
	fp.link("time_up", "clock_out")
	var prev := b.put("clock_out", "clock_out", 7, 0)
	var rules: Array = plan.score_rules if plan != null else []
	for i in rules.size():
		var fx := b.put("score_%d" % (i + 1), "effect", 8 + i, 0, _effect_props(rules[i]))
		prev.link("next", fx.id)
		prev = fx
	var result := b.put("result", "show_result", 8 + rules.size(), 0)
	prev.link("next", result.id)
	result.link("next", "end")
	b.put("end", "day_end", 9 + rules.size(), 0)
	return g


## 正常走到的结局天：人事日志 → 结局对话 → 结局卡。
static func ending_body(ending: String) -> flow_graph:
	var g := flow_graph.new()
	var b := _Builder.new(g)
	b.put("start", "start", 0, 0).link("next", "log")
	b.put("log", "show_log", 1, 0).link("next", "story")
	b.put("story", "story_bubble", 2, 0, {"layer": "story", "source": {"ending": ending}}).link("next", "card")
	b.put("card", "show_ending", 3, 0, {"ending": ending}).link("next", "end")
	b.put("end", "day_end", 4, 0)
	return g


## 被开除：直接出结局卡。
static func fired_body(ending: String) -> flow_graph:
	var g := flow_graph.new()
	var b := _Builder.new(g)
	b.put("start", "start", 0, 0).link("next", "card")
	b.put("card", "show_ending", 1, 0, {"ending": ending}).link("next", "end")
	b.put("end", "day_end", 2, 0)
	return g


## 把一份 .story 原文按块切开：[{"kind": "mail", "id": "day3_rick", "header": "[mail day3_rick …]", "body": "…"}]。
## 跟在剧情 / 桥段后面的 [dialogue x] 并进前一段的 body（连块头一起），解析时它们还挂在同一段对话上。
## 第一个块之前的注释丢掉。
static func split_blocks(text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current: Dictionary = {}
	for raw in text.replace("\r\n", "\n").split("\n"):
		var line := String(raw)
		var stripped := line.strip_edges()
		if stripped.begins_with("[") and stripped.ends_with("]"):
			var parts := stripped.substr(1, stripped.length() - 2).strip_edges().split(" ", false)
			var kind := String(parts[0]).to_lower() if parts.size() > 0 else ""
			if kind == "dialogue" and not current.is_empty() and current["kind"] in DIALOGUE_OWNERS:
				current["lines"].append(line)
				continue
			current = {"kind": kind, "id": String(parts[1]) if parts.size() > 1 else "",
				"header": stripped, "lines": PackedStringArray()}
			result.append(current)
		elif not current.is_empty():
			current["lines"].append(line)
	for blk in result:
		blk["body"] = "\n".join(blk["lines"]).strip_edges()
		blk.erase("lines")
	return result


## 某种块（[story] / [caller] / …）在每种语言里的 body：{"zh": …, "en": …}。哪种语言没有就不写。
static func _block_text(blocks: Dictionary, kind: String) -> Dictionary:
	var result := {}
	for loc in blocks:
		for blk in blocks[loc]:
			if blk["kind"] == kind:
				result[loc] = blk["body"]
				break
	return result


## 发信节点的参数：名单、随机信配置（按中文那份剧本），加上每封剧情信每种语言的原文。
static func _mail_props(plan: day_plan, blocks: Dictionary) -> Dictionary:
	var props := {"filler": -1, "filler_exclude": [], "roster": [], "conditional_roster": [], "mails": []}
	if plan != null:
		props["filler"] = plan.filler_emails
		props["filler_exclude"] = Array(plan.filler_exclude).map(func(a): return String(a))
		props["roster"] = Array(plan.story_roster).map(func(a): return String(a))
		for rule in plan.conditional_roster:
			props["conditional_roster"].append({"name": String(rule.employee_name), "if": rule.condition})
	var base: Array = blocks.get(BASE_LOCALE, [])
	for blk in base:
		if blk["kind"] != "mail":
			continue
		var script := {}
		for loc in blocks:
			for other in blocks[loc]:
				if other["kind"] == "mail" and other["id"] == blk["id"]:
					script[loc] = other["header"] + "\n" + other["body"]
					break
		props["mails"].append({"id": blk["id"], "script": script})
	return props


## 桥段「今天播过了」的 flag，和 event_page.flag_for 拼出来的名字一样。
static func event_flag(key: StringName, day: int) -> String:
	return "event_%s_day_%d" % [key, day]


static func _has_event(plan: day_plan, key: StringName) -> bool:
	if plan == null:
		return false
	var c := plan.event_for(key)
	return c != null and not c.is_empty()


## [score] 的一条规则 → 效果节点的参数。
static func _effect_props(rule: score_rule) -> Dictionary:
	var deltas := {}
	var e: story_effect = rule.effect
	if e != null:
		for pair in [["A", e.a_delta], ["B", e.b_delta], ["C", e.c_delta], ["D", e.d_delta]]:
			if pair[1] != 0:
				deltas[pair[0]] = pair[1]
	var props := {"if": rule.condition, "deltas": deltas}
	if e != null and not e.set_flags.is_empty():
		props["set_flags"] = Array(e.set_flags).map(func(f): return String(f))
	return props


## ui.csv 里一条文字的全部语言：{"zh": …, "en": …}。
static func _ui_text(key: String) -> Dictionary:
	var f := FileAccess.open(UI_CSV, FileAccess.READ)
	if f == null:
		return {"zh": key}
	var header := f.get_csv_line()
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() > 0 and line[0] == key:
			var result := {}
			for i in range(1, mini(header.size(), line.size())):
				result[header[i]] = line[i]
			return result
	return {"zh": key}


## 摆节点用的小帮手：按格子放位置。
class _Builder:
	extends RefCounted
	var g: flow_graph

	func _init(p_g: flow_graph) -> void:
		g = p_g

	func put(id: String, type: String, column: int, row: int, props := {}) -> flow_node:
		var n := g.add(flow_node.new(id, type))
		n.pos = Vector2(column * 220.0, row * ROW)
		n.props = props
		return n

	## 挂在自由环节 listen 上的一个可互动物件。
	func listen(fp: flow_node, obj: String, column: int, row: int, extra := {}) -> flow_node:
		var props := {"object": obj, "unlock": "", "repeat": true, "non_blocking": false}
		props.merge(extra, true)
		var n := put(obj, "interactable", column, row, props)
		fp.link("listen", n.id, false)
		return n
