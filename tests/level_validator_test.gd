extends Node

## 关卡引擎第 0 阶段的自测：数据模型、读写、校验器。跑法见 tests/run_tests.ps1。
##
## 每个用例都从一份合法的小关卡出发，只改一处，断言报出来的正好是那条错误、
## 位置也对——「精准报出原因」是这个校验器存在的意义。

const TEST_LEVEL := "__validator_test"

var _passed := 0
var _failed := 0
var _fail_lines: Array[String] = []
var _section := ""


func _ready() -> void:
	_test_valid_level()
	_test_outer_counts()
	_test_outer_isolated_and_trapped()
	_test_outer_nodes()
	_test_settings_and_world()
	_test_ports()
	_test_inner_structure()
	_test_inner_chains()
	_test_inner_props()
	_test_logic()
	_test_scripts()
	_test_room_objects()
	_test_conditions()
	_test_error_text()
	_test_round_trip()
	_test_store()
	_test_loc_text()
	_report()


# ── 一份合法的小关卡 ─────────────────────────────────────
#
#   day_1(start) → br ─case_1(score.A>=2)→ end_a
#                     └else→ day_2 → jump(+0) → end_b
#   被开除去 end_b。每天里面都是：
#   start → s1 → fp ─listen→ ia(laptop) → fp
#                  └time_up→ fx → res → end

func _valid() -> level_doc:
	var doc := level_doc.create()
	doc.world["objects"] = [{"id": "laptop", "name": {"zh": "电脑"}}]
	doc.settings["fired_ending"] = "end_b"
	var g := doc.graph
	_day(g, "day_1", "start").link("next", "br")
	var br := g.add(flow_node.new("br", "brancher"))
	br.props["cases"] = [{"if": "score.A>=2"}]
	br.link("case_1", "end_a")
	br.link("else", "day_2")
	_day(g, "day_2", "normal").link("next", "jump")
	var jump := g.add(flow_node.new("jump", "jumper"))
	jump.props = {"mode": "add", "value": 0}
	jump.link("next", "end_b")
	_day(g, "end_a", "ending")
	_day(g, "end_b", "ending")
	return doc


func _day(g: flow_graph, id: String, role: String) -> flow_node:
	var n := g.add(flow_node.new(id, "day"))
	n.props = {"role": role, "name": {"zh": id}}
	n.body = _valid_body()
	return n


func _valid_body() -> flow_graph:
	var g := flow_graph.new()
	_inner(g, "start", "start").link("next", "s1")
	var s1 := _inner(g, "s1", "story_bubble")
	s1.props["script"] = {"zh": "them: 早上好。"}
	s1.link("next", "fp")
	var fp := _inner(g, "fp", "free_play")
	fp.link("listen", "ia", false)
	fp.link("time_up", "fx")
	var ia := _inner(g, "ia", "interactable")
	ia.props = {"object": "laptop", "unlock": "", "repeat": true}
	ia.link("next", "fp")
	var fx := _inner(g, "fx", "effect")
	fx.props = {"if": "did(fire,*any)", "deltas": {"A": 1}}
	fx.link("next", "res")
	_inner(g, "res", "show_result").link("next", "end")
	_inner(g, "end", "day_end")
	return g


func _inner(g: flow_graph, id: String, type: String) -> flow_node:
	return g.add(flow_node.new(id, type))


func _body(doc: level_doc, day := "day_1") -> flow_graph:
	return doc.graph.node(day).body


## 「代码@位置」列表，断言用。
func _codes(doc: level_doc) -> Array[String]:
	var result: Array[String] = []
	for e in level_validator.validate(doc):
		result.append("%s@%s" % [e.code, e.location()])
	return result


func _expect_exactly(label: String, doc: level_doc, expected: Array) -> void:
	var got := _codes(doc)
	var want: Array[String] = []
	want.assign(expected)
	got.sort()
	want.sort()
	_record(label, got == want, "实际 %s，期望 %s" % [got, want])


func _expect_has(label: String, doc: level_doc, code_at: String) -> void:
	var got := _codes(doc)
	_record(label, code_at in got, "实际 %s，期望含 %s" % [got, code_at])


# ── 用例 ─────────────────────────────────────────────────

func _test_valid_level() -> void:
	_section = "合法关卡"
	_expect_exactly("一条错误都没有", _valid(), [])
	_is_true("is_valid", level_validator.is_valid(_valid()))


func _test_outer_counts() -> void:
	_section = "初始天 / 结局天数量"
	var doc := _valid()
	doc.graph.node("day_2").props["role"] = "start"
	_expect_exactly("两个初始天", doc, ["START_COUNT@"])

	doc = _valid()
	doc.graph.node("day_1").props["role"] = "normal"
	_expect_exactly("没有初始天时只报数量，不把每个节点都报成孤立", doc, ["START_COUNT@"])

	doc = _valid()
	for id in ["end_a", "end_b"]:
		doc.graph.node(id).props["role"] = "normal"
	_expect_has("没有结局天", doc, "NO_ENDING@")
	_expect_has("被开除去的不再是结局天", doc, "FIRED_ENDING_NOT_ENDING@")


func _test_outer_isolated_and_trapped() -> void:
	_section = "孤立 / 困住"
	var doc := _valid()
	_day(doc.graph, "day_x", "normal").link("next", "end_a")
	_expect_exactly("孤立的天节点", doc, ["UNREACHABLE@day_x"])

	doc = _valid()
	var br := doc.graph.add(flow_node.new("br_x", "brancher"))
	br.link("else", "end_a")
	_expect_exactly("孤立的分化器", doc, ["UNREACHABLE@br_x"])

	doc = _valid()
	_day(doc.graph, "day_3", "normal").link("next", "day_3")
	doc.graph.node("br").link("else", "day_3")
	# day_2 → jump 这一支被切掉了，跟着报孤立是对的；end_b 是被开除的去处，算入口。
	_expect_exactly("自己绕圈、走不到结局的天", doc,
		["NO_PATH_TO_END@day_3", "UNREACHABLE@day_2", "UNREACHABLE@jump"])


func _test_outer_nodes() -> void:
	_section = "外层节点"
	var doc := _valid()
	doc.graph.node("br").unlink("else")
	_expect_exactly("分化器缺 else（原来接在 else 后面的那一支跟着孤立）", doc,
		["PORT_MISSING@br", "UNREACHABLE@day_2", "UNREACHABLE@jump"])

	doc = _valid()
	doc.graph.node("br").props["cases"] = [{"if": "score.Z>=2"}]
	_expect_exactly("分化器条件写错", doc, ["BAD_CONDITION@br"])

	doc = _valid()
	doc.graph.node("br").props["cases"] = [{"if": "score.A>=2"}, {"if": "flag:x"}]
	_expect_exactly("多一个条件就多一个必须接的出口", doc, ["PORT_MISSING@br"])

	doc = _valid()
	doc.graph.node("end_a").link("next", "day_2")
	_expect_exactly("结局天有出口（不重复报未知出口）", doc, ["ENDING_HAS_EXIT@end_a"])

	doc = _valid()
	doc.graph.node("jump").props["mode"] = "teleport"
	_expect_exactly("跳转器 mode 不认识", doc, ["BAD_JUMP_MODE@jump"])

	doc = _valid()
	doc.graph.node("day_2").props["role"] = "boss"
	_expect_has("role 不认识", doc, "BAD_ROLE@day_2")

	doc = _valid()
	doc.graph.add(flow_node.new("weird", "portal"))
	_expect_has("外层类型不认识", doc, "UNKNOWN_TYPE@weird")


func _test_settings_and_world() -> void:
	_section = "背景设定 / 世界表"
	var doc := _valid()
	doc.settings["fired_ending"] = ""
	_expect_exactly("没填被开除去哪", doc, ["FIRED_ENDING_MISSING@"])

	doc = _valid()
	_day(doc.graph, "end_fired", "ending")
	doc.settings["fired_ending"] = "end_fired"
	_expect_exactly("只有被开除才去得了的结局不算孤立", doc, [])

	doc = _valid()
	doc.settings["fired_ending"] = "day_2"
	_expect_exactly("被开除指向普通天", doc, ["FIRED_ENDING_NOT_ENDING@"])

	doc = _valid()
	doc.settings["lives"] = 5
	_expect_exactly("命数不在选项里", doc, ["LIVES_INVALID@"])

	doc = _valid()
	doc.settings["variables"].append({"id": "A", "kind": "score"})
	_expect_exactly("变量重名", doc, ["DUP_VARIABLE@"])

	doc = _valid()
	doc.world["objects"].append({"id": "laptop"})
	_expect_exactly("世界表 id 重复", doc, ["DUP_WORLD_ID@"])


func _test_ports() -> void:
	_section = "连线"
	var doc := _valid()
	doc.graph.node("day_2").link("next", "nowhere")
	_expect_has("接到不存在的节点", doc, "BAD_TARGET@day_2")

	doc = _valid()
	_body(doc).node("start").link("next", "ia")
	_expect_exactly("开始节点直接接可互动物件", doc, ["WRONG_TARGET_TYPE@day_1/start", "UNREACHABLE@day_1/s1"])

	doc = _valid()
	_body(doc).node("res").link("next", "start")
	_expect_has("连回开始节点", doc, "WRONG_TARGET_TYPE@day_1/res")

	doc = _valid()
	_body(doc).node("s1").link("next", "end", false)
	_expect_exactly("单出口接了两个", doc, ["TOO_MANY_TARGETS@day_1/s1"])

	doc = _valid()
	_body(doc).node("s1").link("sideways", "end")
	_expect_exactly("没有这个出口", doc, ["UNKNOWN_PORT@day_1/s1"])


func _test_inner_structure() -> void:
	_section = "天内图结构"
	var doc := _valid()
	doc.graph.node("day_2").body = null
	_expect_exactly("天节点没有天内图", doc, ["DAY_BODY_MISSING@day_2"])

	doc = _valid()
	_body(doc).nodes.erase("start")
	_expect_exactly("天内图没有开始", doc, ["DAY_START_COUNT@day_1"])

	doc = _valid()
	_inner(_body(doc), "start2", "start").link("next", "fp")
	_expect_has("天内图两个开始", doc, "DAY_START_COUNT@day_1")

	doc = _valid()
	_body(doc).node("fp").link("time_up", "fp")
	_expect_has("到点又回自由环节：天结束不了", doc, "DAY_NO_END@day_1")
	_expect_has("自由环节被困住", doc, "NO_PATH_TO_END@day_1/fp")

	doc = _valid()
	_inner(_body(doc), "lonely", "story_bubble").link("next", "fp")
	_expect_exactly("孤立的剧情 bubble", doc, ["UNREACHABLE@day_1/lonely"])

	doc = _valid()
	_body(doc).add(flow_node.new("blob", "hologram"))
	_expect_has("内层类型不认识", doc, "UNKNOWN_TYPE@day_1/blob")


func _test_inner_chains() -> void:
	_section = "强制链"
	var doc := _valid()
	var g := _body(doc)
	_inner(g, "s2", "story_bubble").link("next", "s1")
	g.node("s1").link("next", "s2")
	var codes := _codes(doc)
	_is_true("强制链绕圈", "CHAIN_LOOP@day_1/s1" in codes, str(codes))
	_eq("一个圈只报一次", codes.count("CHAIN_LOOP@day_1/s1") + codes.count("CHAIN_LOOP@day_1/s2"), 1)
	_is_false("圈里的节点不再报走不到结束", "NO_PATH_TO_END@day_1/s2" in codes, str(codes))

	doc = _valid()
	_body(doc).node("fp").unlink("listen")
	_expect_exactly("可互动物件没人 listen（不报成孤立）", doc, ["NOT_LISTENED@day_1/ia"])

	doc = _valid()
	_body(doc).node("fp").unlink("time_up")
	_expect_has("自由环节没接到点", doc, "PORT_MISSING@day_1/fp")

	doc = _valid()
	_body(doc).node("fx").unlink("next")
	_expect_has("强制元件没接下一步", doc, "PORT_MISSING@day_1/fx")


func _test_inner_props() -> void:
	_section = "元件参数"
	var doc := _valid()
	_body(doc).node("ia").props["object"] = "toaster"
	_expect_exactly("引用不存在的物件", doc, ["UNKNOWN_OBJECT@day_1/ia"])

	doc = _valid()
	_body(doc).node("ia").props["unlock"] = "flag:"
	_expect_exactly("解锁条件写错", doc, ["BAD_CONDITION@day_1/ia"])

	doc = _valid()
	_body(doc).node("fx").props["deltas"] = {"Q": 1}
	_expect_exactly("效果用了没定义的变量", doc, ["UNKNOWN_VARIABLE@day_1/fx"])

	doc = _valid()
	var wb := _inner(_body(doc), "wb", "window_bubble")
	wb.props["object"] = "phone"
	wb.link("next", "fp")
	_body(doc).node("s1").link("next", "wb")
	_expect_exactly("视窗 bubble 引用不存在的物件", doc, ["UNKNOWN_OBJECT@day_1/wb"])


## 条件分支（if）、自定义变量、绕过 if 的强制链圈。
func _test_logic() -> void:
	_section = "逻辑"
	var doc := _valid()
	var g := _body(doc)
	var check := _inner(g, "check", "if")
	check.props["cases"] = [{"if": "flag:x and var.A>=1"}]
	check.link("case_1", "fp")
	check.link("else", "fp")
	g.node("s1").link("next", "check")
	_expect_exactly("合法的条件分支", doc, [])

	check.unlink("else")
	_expect_exactly("条件分支缺 else", doc, ["PORT_MISSING@day_1/check"])

	check.link("else", "fp")
	check.props["cases"] = [{"if": "flag:"}]
	_expect_exactly("条件分支的条件写错", doc, ["BAD_CONDITION@day_1/check"])

	check.props["cases"] = [{"if": "var.mails_read>=3"}]
	_expect_exactly("条件里用了没定义的变量", doc, ["UNKNOWN_VARIABLE@day_1/check"])
	doc.settings["variables"].append({"id": "mails_read", "kind": "counter"})
	_expect_exactly("定义之后就合法", doc, [])

	check.props["cases"] = [{"if": "inbox_empty"}]
	_expect_exactly("inbox_empty 是合法的原子", doc, [])

	doc = _valid()
	g = _body(doc)
	check = _inner(g, "check", "if")
	check.props["cases"] = [{"if": "flag:x"}]
	check.link("case_1", "s2")
	check.link("else", "fp")
	_inner(g, "s2", "story_bubble").link("next", "check")
	g.node("s1").link("next", "check")
	var codes := _codes(doc)
	_is_true("经过条件分支的强制链绕圈也抓得到", "CHAIN_LOOP@day_1/check" in codes, str(codes))

	doc = _valid()
	g = _body(doc)
	_inner(g, "out", "clock_out").link("next", "res")
	g.node("fp").link("time_up", "out")
	g.node("fx").unlink("next")
	g.node("fx").link("next", "res")
	_body(doc).nodes.erase("fx")
	_expect_exactly("下班元件能接进结算链", doc, [])


## 节点里的文字（2c）：剧情 / 邮件写错要报出是哪种语言、哪个节点。
func _test_scripts() -> void:
	_section = "节点里的文字"
	var doc := _valid()
	var g := _body(doc)
	g.node("s1").props = {"layer": "story", "script": {"zh": "them: 早。", "en": "them: Morning."}}
	_expect_exactly("合法的剧情文字", doc, [])

	g.node("s1").props["script"]["en"] = "them: hi\n[weird]"
	_expect_exactly("英文那份写错", doc, ["BAD_SCRIPT@day_1/s1"])
	var errs := level_validator.validate(doc)
	_eq("报出是哪种语言", errs[0].params.get("locale", "") if not errs.is_empty() else "", "en")

	g.node("s1").props = {"layer": "popup", "script": {}}
	_expect_exactly("layer 不认识", doc, ["BAD_LAYER@day_1/s1"])

	g.node("s1").props = {"layer": "notice", "script": {"zh": "[不是剧本也没关系]"}}
	_expect_exactly("提示框是纯文字，不按剧本解析", doc, [])

	doc = _valid()
	g = _body(doc)
	var mail := _inner(g, "mail", "send_mail")
	mail.props = {"mails": [{"id": "hello", "script": {"zh": "[mail hello from=\"A\"]\nsubject: 嗨\n正文"}}]}
	mail.link("next", "fp")
	g.node("s1").link("next", "mail")
	_expect_exactly("合法的邮件", doc, [])

	mail.props["mails"][0]["script"]["zh"] = "[mail other from=\"A\"]\nsubject: 嗨"
	_expect_exactly("块头 id 和登记的不一样", doc, ["BAD_SCRIPT@day_1/mail"])

	mail.props["mails"][0]["script"]["zh"] = "[mail hello from=\"A\"]\nsubject: 嗨"
	mail.props["conditional_roster"] = [{"name": "Bob", "if": "flag:"}]
	_expect_exactly("条件名单的条件写错", doc, ["BAD_CONDITION@day_1/mail"])

	mail.props.erase("conditional_roster")
	var g2 := _body(doc, "day_2")
	var mail2 := _inner(g2, "mail", "send_mail")
	mail2.props = mail.props.duplicate(true)
	mail2.link("next", "fp")
	g2.node("s1").link("next", "mail")
	_expect_exactly("两天里有同一个邮件 id", doc, ["DUP_MAIL_ID@day_2/mail"])


## 房间物件（第 3 阶段）：弹窗类型、素材、视窗 bubble 指向没弹窗的物件。
func _test_room_objects() -> void:
	_section = "房间物件"
	var doc := _valid()
	doc.world["objects"] = level_converter.room_objects()
	_expect_exactly("转换器给的整套房间是合法的", doc, [])

	doc.world["objects"][0]["window"] = "fridge"
	_expect_exactly("弹窗类型不认识", doc, ["BAD_WINDOW@"])

	doc = _valid()
	doc.world["objects"] = level_converter.room_objects()
	doc.world["objects"][0]["texture"] = "theme/items/nope.png"
	_expect_exactly("贴图找不到", doc, ["MISSING_ASSET@"])

	doc = _valid()
	doc.world["objects"] = level_converter.room_objects()
	var wb := _inner(_body(doc), "wb", "window_bubble")
	wb.props["object"] = "door"
	wb.link("next", "fp")
	_body(doc).node("s1").link("next", "wb")
	_expect_exactly("门没有弹窗，视窗 bubble 打不开", doc, ["NO_WINDOW@day_1/wb"])
	wb.props["object"] = "laptop"
	_expect_exactly("电脑有弹窗", doc, [])


## 条件语法的新原子：自定义变量、收件箱。
func _test_conditions() -> void:
	_section = "条件原子"
	_eq("var. 语法合法", story_condition.validate("var.mails_read>=3"), "")
	_is_false("var. 后面要写名字", story_condition.validate("var.>=3").is_empty())
	GameState.reset()
	GameState.add_var(&"mails_read", 3)
	_is_true("计数器到 3", story_condition.eval("var.mails_read>=3"))
	_is_false("计数器没到 4", story_condition.eval("var.mails_read>=4"))
	GameState.add_score(GameState.SCORE_A, 2)
	_is_true("var.A 和 score.A 读的是同一个值", story_condition.eval("var.A==2 and score.A==2"))
	_is_false("没有收件箱（不在游戏场景里）时 inbox_empty 不成立", story_condition.eval("inbox_empty"))
	GameState.reset()


func _test_error_text() -> void:
	_section = "错误文字"
	var e := level_error.new("PORT_MISSING", {"port": "else"}, "", "br")
	_eq("外层错误", e.describe(), "br 的出口「else」必须接上")
	e = level_error.new("UNKNOWN_OBJECT", {"object": "toaster"}, "day_1", "ia")
	_eq("内层错误带天节点前缀", e.describe(), "[day_1] ia 引用了不存在的房间物件「toaster」")
	_eq("位置", e.location(), "day_1/ia")
	for code in level_error.TEMPLATES:
		_is_false("模板里没有漏掉的占位符：%s" % code,
			level_error.new(code, {"count": 0, "role": "", "mode": "", "target": "", "value": 0,
				"options": "", "id": "", "table": "", "object": "", "type": "", "port": "",
				"target_type": "", "detail": "", "layer": "", "locale": "", "other": "", "window": "", "asset": ""}, "d", "n").describe().contains("{"))


func _test_round_trip() -> void:
	_section = "存取往返"
	var doc := _valid()
	var text := JSON.stringify(doc.to_dict())
	var back := level_doc.from_dict(JSON.parse_string(text))
	_eq("JSON 往返后内容不变", JSON.stringify(back.to_dict()), text)
	_is_true("往返后命数还是整数", back.settings["lives"] is int)
	_is_true("往返后还是合法的", level_validator.is_valid(back))
	_eq("坐标", back.graph.node("br").pos, Vector2.ZERO)

	var raw := {"nodes": {"a": {"type": "start", "outs": {"next": "b"}}}}
	_eq("手写的单个字串出口也认", flow_graph.from_dict(raw).node("a").targets("next"), ["b"] as Array[String])


func _test_store() -> void:
	_section = "读写"
	var path := level_store.USER_DIR + TEST_LEVEL + level_store.EXT
	var doc := _valid()
	doc.graph.node("br").pos = Vector2(120, -40)
	_eq("存到 user://", level_store.save_level(TEST_LEVEL, doc), "")
	var r := level_store.load_level(TEST_LEVEL)
	_eq("读回来没有错误", r.error, "")
	_eq("读的是 user:// 那份", r.path, path)
	_is_true("读回来还是合法的", r.doc != null and level_validator.is_valid(r.doc))
	if r.doc:
		_eq("坐标存住了", r.doc.graph.node("br").pos, Vector2(120, -40))

	_write_raw(path, "{ \"format\": \"offast-level\", ")
	_is_true("JSON 坏掉报行号", level_store.read(path).error.contains("JSON"))

	_write_raw(path, JSON.stringify({"format": "something-else", "version": 1}))
	_is_true("不是关卡文件", level_store.read(path).error.contains("format"))

	_write_raw(path, JSON.stringify({"format": level_doc.FORMAT, "version": level_doc.VERSION + 1}))
	_is_true("版本比代码新就拒绝", level_store.read(path).doc == null)

	_is_true("找不到文件", not level_store.read("user://levels/__nope.level.json").error.is_empty())
	DirAccess.remove_absolute(path)


func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _test_loc_text() -> void:
	_section = "多语言文字"
	var v := {"zh": "电脑", "en": "Laptop"}
	_eq("指定语言", level_doc.loc_text(v, "en"), "Laptop")
	_eq("没有这个语言退回中文", level_doc.loc_text(v, "ja"), "电脑")
	_eq("纯字串原样返回", level_doc.loc_text("hi", "en"), "hi")
	_eq("空值", level_doc.loc_text({}, "en"), "")


# ── 断言 ─────────────────────────────────────────────────

func _eq(label: String, actual: Variant, expected: Variant) -> void:
	_record(label, actual == expected, "实际 %s，期望 %s" % [actual, expected])


func _is_true(label: String, cond: bool, detail := "") -> void:
	_record(label, cond, "期望为真" if detail.is_empty() else detail)


func _is_false(label: String, cond: bool, detail := "") -> void:
	_record(label, not cond, "期望为假" if detail.is_empty() else detail)


func _record(label: String, ok: bool, detail: String) -> void:
	if ok:
		_passed += 1
		return
	_failed += 1
	_fail_lines.append("  ✗ [%s] %s —— %s" % [_section, label, detail])


func _report() -> void:
	print("\n=========== level_validator_test ==========")
	if _failed == 0:
		print("全部通过：%d 项" % _passed)
	else:
		print("通过 %d 项，失败 %d 项：" % [_passed, _failed])
		for line in _fail_lines:
			print(line)
	print("===========================================\n")
	get_tree().quit(1 if _failed > 0 else 0)
