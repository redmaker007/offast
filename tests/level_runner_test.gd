extends Node

## 关卡引擎第 1 阶段的自测：转换出来的关卡、外层解释器（level_runner）。跑法见 tests/run_tests.ps1。
##
## 第 1 阶段的硬要求是「线性图玩起来和原来一模一样」，所以这里重点对照：
##   - res://levels/main.level.json 的天数、剧本、结局分化器和 .story 内容对得上；
##   - 各种局面下，结局分化器选出来的结局和原来 world.story 规则表查出来的一致。
## 整局流程（每天怎么推进、通关、被开除）在 flow_test 里照旧跑，那边不用改。

const STORY_DIR := "res://story/zh"

var _passed := 0
var _failed := 0
var _fail_lines: Array[String] = []
var _section := ""

var _world: world_book


func _ready() -> void:
	_world = load(STORY_DIR + "/world.story") as world_book
	_test_committed_level()
	_test_linear_walk()
	_test_endings_match_rules()
	_test_fire()
	_test_jumper()
	_test_branch_loop_guard()
	_test_save_load()
	_test_load_failure()
	_report()


func _main() -> level_runner:
	return level_runner.open("main")


func _test_committed_level() -> void:
	_section = "main.level.json"
	var runner := _main()
	_is_true("读得进来且合法", runner.is_valid(), runner.describe_errors())
	if runner.doc == null:
		return
	var g := runner.doc.graph

	var day_count := 0
	while ResourceLoader.exists("%s/days/day_%d.story" % [STORY_DIR, day_count + 1]):
		day_count += 1
	_eq("上班天数和 day_N.story 一样多", runner.total_days(), day_count)
	for i in range(1, day_count + 1):
		var n := g.node("day_%d" % i)
		_is_true("有 day_%d" % i, n != null)
		if n:
			_eq("day_%d 用第 %d 天的剧本" % [i, i], int(n.props.get("plan", 0)), i)

	var br := g.node("ending_branch")
	_is_true("最后一天接结局分化器", g.node("day_%d" % day_count).target("next") == "ending_branch")
	var cases := node_types.branch_cases(br)
	_eq("分化器条件数和 [ending] 规则数一样", cases.size(), _world.ending_rules.size())
	for i in mini(cases.size(), _world.ending_rules.size()):
		var rule: ending_rule = _world.ending_rules[i]
		_eq("第 %d 条条件照抄" % (i + 1), str(cases[i]["if"]), rule.condition)
		_eq("第 %d 条去对应结局" % (i + 1), br.target(node_types.case_port(i)), "end_" + String(rule.ending))
	_eq("else 走兜底 C", br.target("else"), "end_C")
	_eq("被开除去 E", runner.doc.settings["fired_ending"], "end_E")
	_eq("三条命", runner.lives(), 3)


func _test_linear_walk() -> void:
	_section = "线性推进"
	var runner := _main()
	runner.start()
	_eq("开局在 day_1", runner.current, "day_1")
	_eq("第 1 天", runner.day, 1)
	for i in range(2, runner.total_days() + 1):
		runner.advance()
		_eq("第 %d 天的节点" % i, runner.current, "day_%d" % i)
		_eq("第 %d 天的天数" % i, runner.day, i)
		_eq("第 %d 天的剧本" % i, runner.plan_day(), i)
		_is_false("第 %d 天不是结局" % i, runner.is_ending())
	_eq("流水账记了每一天", runner.history.size(), runner.total_days())
	_eq("流水账第 3 条", runner.history[2], {"seq": 3, "node": "day_3", "day": 3})
	GameState.reset()
	runner.advance()
	_is_true("最后一天之后到结局天", runner.is_ending())


## 和 faction_test 里那几种局面一样，逐一对照「关卡图」和「原来的规则表」。
func _test_endings_match_rules() -> void:
	_section = "结局和原规则表一致"
	var scenarios := {
		"倒向 A 且批了瑞克": func() -> void:
			GameState.add_score(GameState.SCORE_A, 3)
			GameState.log_personnel(5, {"employee": "Rick", "actual": {"Promotion": true}}),
		"倒向 B 且给自己批了": func() -> void:
			GameState.add_score(GameState.SCORE_B, 3)
			GameState.log_personnel(5, {"employee": String(GameState.SELF), "actual": {"Promotion": true}}),
		"倒向 A 却没照做": func() -> void:
			GameState.add_score(GameState.SCORE_A, 3),
		"证据齐全清掉两个头目": func() -> void:
			GameState.add_score(GameState.SCORE_D, 3)
			GameState.set_flag(&"has_tape")
			GameState.set_flag(&"has_photo")
			GameState.levels[&"Bob"] = 4
			GameState.log_personnel(5, {"employee": "Banner", "actual": {"Fire": true}})
			GameState.log_personnel(5, {"employee": "Roderick", "actual": {"Fire": true}}),
		"证据不齐": func() -> void:
			GameState.add_score(GameState.SCORE_D, 3)
			GameState.set_flag(&"has_tape"),
		"什么都没干": func() -> void: pass,
	}
	var expected := {"倒向 A 且批了瑞克": &"A", "倒向 B 且给自己批了": &"B", "倒向 A 却没照做": &"E",
		"证据齐全清掉两个头目": &"D", "证据不齐": &"C", "什么都没干": &"C"}
	for label in scenarios:
		GameState.reset()
		scenarios[label].call()
		var runner := _main()
		runner.start()
		while not runner.is_ending() and runner.advance() != null:
			pass
		_eq("%s：关卡图" % label, runner.ending_id(), _by_rules())
		_eq("%s：结局" % label, runner.ending_id(), expected[label])
	GameState.reset()


## 原来 ending_director._decide 的查法。
func _by_rules() -> StringName:
	for rule in _world.ending_rules:
		if story_condition.eval(rule.condition):
			return rule.ending
	return &"C"


func _test_fire() -> void:
	_section = "被开除"
	var runner := _main()
	runner.start()
	runner.advance()
	runner.fire()
	_eq("跳到被开除的结局天", runner.current, "end_E")
	_is_true("是结局", runner.is_ending())
	_eq("结局 id", runner.ending_id(), &"E")


## day_1 → 跳转器 → day_2 → 跳转器 → day_3 → 结局。
func _jump_doc(mode1: String, value1: int, mode2: String, value2: int) -> level_doc:
	var doc := level_doc.create()
	doc.settings["fired_ending"] = "end"
	var g := doc.graph
	for id in ["day_1", "day_2", "day_3", "end"]:
		var n := g.add(flow_node.new(id, "day"))
		n.props = {"role": "normal"}
		n.body = level_converter._work_day_body()
	g.node("day_1").props["role"] = "start"
	g.node("end").props["role"] = "ending"
	g.node("end").body = level_converter._ending_body()
	var j1 := g.add(flow_node.new("j1", "jumper"))
	j1.props = {"mode": mode1, "value": value1}
	var j2 := g.add(flow_node.new("j2", "jumper"))
	j2.props = {"mode": mode2, "value": value2}
	g.node("day_1").link("next", "j1")
	j1.link("next", "day_2")
	g.node("day_2").link("next", "j2")
	j2.link("next", "day_3")
	g.node("day_3").link("next", "end")
	return doc


func _test_jumper() -> void:
	_section = "天数跳转器"
	var runner := level_runner.new()
	runner.set_doc(_jump_doc("set", 7, "add", -3))
	_is_true("测试关卡合法", runner.is_valid(), runner.describe_errors())
	runner.start()
	runner.advance()
	_eq("set 7：下一天就是第 7 天", runner.day, 7)
	runner.advance()
	_eq("add -3：本来第 8 天，变成第 5 天", runner.day, 5)
	runner.advance()
	_eq("之后照常 +1", runner.day, 6)
	_eq("流水账按经过的顺序记，天数可以倒退",
		runner.history.map(func(h): return h["day"]), [1, 7, 5, 6])

	runner.set_doc(_jump_doc("add", 0, "add", 0))
	runner.start()
	runner.advance()
	_eq("add 0 等于没跳", runner.day, 2)


func _test_branch_loop_guard() -> void:
	_section = "分化器绕圈保护"
	var doc := level_doc.create()
	doc.settings["fired_ending"] = "end"
	var g := doc.graph
	var d1 := g.add(flow_node.new("day_1", "day"))
	d1.props = {"role": "start"}
	d1.body = level_converter._work_day_body()
	var e := g.add(flow_node.new("end", "day"))
	e.props = {"role": "ending"}
	e.body = level_converter._ending_body()
	var b1 := g.add(flow_node.new("b1", "brancher"))
	b1.props["cases"] = [{"if": "flag:never_set"}]
	b1.link("case_1", "end")
	b1.link("else", "b2")
	var b2 := g.add(flow_node.new("b2", "brancher"))
	b2.link("else", "b1")
	d1.link("next", "b1")
	var runner := level_runner.new()
	runner.set_doc(doc)
	_is_true("校验器认为合法（条件成立时走得到结局）", runner.is_valid(), runner.describe_errors())
	GameState.reset()
	runner.start()
	_eq("条件一直不成立时 advance 返回 null，不卡死", runner.advance(), null)
	_eq("停在原地", runner.current, "day_1")


func _test_save_load() -> void:
	_section = "存读档"
	var runner := _main()
	runner.start()
	runner.advance()
	runner.advance()
	var saved := runner.save_data()
	var back := _main()
	back.load_data(JSON.parse_string(JSON.stringify(saved)))
	_eq("读回当前节点", back.current, "day_3")
	_eq("读回天数", back.day, 3)
	_eq("读回流水账", back.history.size(), 3)
	back.advance()
	_eq("读档后接着走", back.current, "day_4")

	var old := _main()
	old.load_data({}, 4)
	_eq("旧存档只有 current_day：按 day_N 找回去", old.current, "day_4")
	_eq("旧存档的天数", old.day, 4)


func _test_load_failure() -> void:
	_section = "读不进来"
	var runner := level_runner.open("__no_such_level")
	_is_false("不合法", runner.is_valid())
	_eq("报 LOAD_FAILED", runner.errors[0].code if not runner.errors.is_empty() else "", "LOAD_FAILED")


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
	print("\n============ level_runner_test ============")
	if _failed == 0:
		print("全部通过：%d 项" % _passed)
	else:
		print("通过 %d 项，失败 %d 项：" % [_passed, _failed])
		for line in _fail_lines:
			print(line)
	print("===========================================\n")
	get_tree().quit(1 if _failed > 0 else 0)
