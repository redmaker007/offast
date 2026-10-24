extends Node

## 天内图解释器（day_runner）的自测，用假 host，不起游戏场景。跑法见 tests/run_tests.ps1。
##
## 覆盖：开场链走到自由环节、点物件跑强制链再回来、解锁条件、不可重复、
## 强制链期间点物件没反应（non_blocking 例外）、强制链期间到点先记着、
## 条件分支、效果节点、门的瞬发判定、读档退回自由环节。
## 整局在游戏里怎么跑，flow_test / faction_test 照旧覆盖。

var _passed := 0
var _failed := 0
var _fail_lines: Array[String] = []
var _section := ""


## 假 host：记下执行过的元件；类型在 waits 里的「要等」，等测试手动 step_done。
class FakeHost:
	extends RefCounted
	var log: Array[String] = []
	var waits: Array = ["story_bubble", "show_result"]
	var free_entries := 0

	func run_step(n: flow_node) -> bool:
		log.append(n.id)
		return n.type in waits

	func enter_free_play(_n: flow_node) -> void:
		free_entries += 1


func _ready() -> void:
	_test_opening_to_free_play()
	_test_click_chain()
	_test_unlock_and_repeat()
	_test_locked_during_chain()
	_test_time_up()
	_test_branch_and_effect()
	_test_door()
	_test_save_abort()
	GameState.reset()
	_report()


##   start → opening(等) → mail → fp ─listen→ laptop → lw(视窗) → fp
##                                  ├listen→ notes(non_blocking) → nw(视窗) → fp
##                                  ├listen→ phone → ev(剧情，等) → fp
##                                  └time_up → out → res(等) → end
func _body() -> flow_graph:
	var g := flow_graph.new()
	_n(g, "start", "start").link("next", "opening")
	_n(g, "opening", "story_bubble").link("next", "mail")
	_n(g, "mail", "send_mail").link("next", "fp")
	var fp := _n(g, "fp", "free_play")
	for pair in [["laptop", "lw"], ["notes", "nw"], ["phone", "ev"]]:
		var ia := _n(g, pair[0], "interactable", {"object": pair[0], "unlock": "", "repeat": true,
			"non_blocking": pair[0] == "notes"})
		ia.link("next", pair[1])
		fp.link("listen", ia.id, false)
		var t := "story_bubble" if pair[1] == "ev" else "window_bubble"
		_n(g, pair[1], t).link("next", "fp")
	fp.link("time_up", "out")
	_n(g, "out", "clock_out").link("next", "res")
	_n(g, "res", "show_result").link("next", "end")
	_n(g, "end", "day_end")
	return g


func _n(g: flow_graph, id: String, type: String, props := {}) -> flow_node:
	var n := g.add(flow_node.new(id, type))
	n.props = props
	return n


func _started(g := _body()) -> Array:
	var host := FakeHost.new()
	var r := day_runner.new()
	r.start(g, host)
	return [r, host]


func _test_opening_to_free_play() -> void:
	_section = "开场"
	var pair := _started()
	var r: day_runner = pair[0]
	var host: FakeHost = pair[1]
	_eq("停在开场剧情等着", [r.mode, r.current], [day_runner.CHAIN, "opening"])
	_eq("还没进自由环节", host.free_entries, 0)
	r.step_done()
	_eq("剧情播完 → 发信 → 自由环节", host.log, ["opening", "mail"] as Array[String])
	_eq("停在自由环节", [r.mode, r.current, r.hub], [day_runner.FREE, "fp", "fp"])
	_eq("进了一次自由环节", host.free_entries, 1)


func _free(g := _body()) -> Array:
	var pair := _started(g)
	pair[0].step_done()
	pair[1].log.clear()
	return pair


func _test_click_chain() -> void:
	_section = "点物件"
	var pair := _free()
	var r: day_runner = pair[0]
	var host: FakeHost = pair[1]
	_is_true("点电脑被接住", r.click("laptop"))
	_eq("开了电脑的视窗", host.log, ["lw"] as Array[String])
	_eq("视窗是瞬间的，马上回到自由环节", r.mode, day_runner.FREE)
	_is_false("没挂在自由环节上的物件点了没反应", r.click("toaster"))

	r.click("phone")
	_eq("点电话播桥段，等着", [r.mode, r.current], [day_runner.CHAIN, "ev"])
	r.step_done()
	_eq("桥段播完回自由环节", r.mode, day_runner.FREE)


func _test_unlock_and_repeat() -> void:
	_section = "解锁 / 不可重复"
	var g := _body()
	g.node("laptop").props["unlock"] = "flag:has_password"
	g.node("phone").props["repeat"] = false
	var pair := _free(g)
	var r: day_runner = pair[0]
	var host: FakeHost = pair[1]
	GameState.reset()
	_is_false("没解锁点了没反应", r.click("laptop"))
	_eq("什么都没执行", host.log, [] as Array[String])
	GameState.set_flag(&"has_password")
	_is_true("条件成立就解锁（每次点击时重新判）", r.click("laptop"))

	_is_true("不可重复的第一次能点", r.click("phone"))
	r.step_done()
	_is_false("第二次没反应", r.click("phone"))
	GameState.reset()


func _test_locked_during_chain() -> void:
	_section = "强制链期间"
	var pair := _free()
	var r: day_runner = pair[0]
	var host: FakeHost = pair[1]
	r.click("phone")
	host.log.clear()
	_is_false("桥段播着时点电脑没反应", r.click("laptop"))
	_is_true("便签不锁，照样能点", r.click("notes"))
	_eq("开了便签的视窗", host.log, ["nw"] as Array[String])
	_eq("正在跑的桥段不受影响", [r.mode, r.current], [day_runner.CHAIN, "ev"])
	r.step_done()
	_eq("桥段播完照常回自由环节", r.mode, day_runner.FREE)


func _test_time_up() -> void:
	_section = "到点"
	var pair := _free()
	var r: day_runner = pair[0]
	var host: FakeHost = pair[1]
	r.click("phone")
	r.time_up()
	_eq("桥段播着时到点：先记着，不打断", [r.current, r.pending_time_up], ["ev", true])
	r.step_done()
	_eq("回到自由环节立刻下班", host.log, ["ev", "out", "res"] as Array[String])
	_eq("停在结算等确认", [r.mode, r.current], [day_runner.CHAIN, "res"])
	var ended := [false]
	r.finished.connect(func(): ended[0] = true)
	r.step_done()
	_is_true("确认之后天结束", ended[0])
	_eq("模式", r.mode, day_runner.ENDED)
	_is_false("天结束之后点物件没反应", r.click("laptop"))


func _test_branch_and_effect() -> void:
	_section = "条件分支 / 效果"
	var g := _body()
	# 电话 → if 今天的来电没接过 → 记下 → 桥段；否则 → 拨号盘
	var check := _n(g, "check", "if", {"cases": [{"if": "not flag:called_today"}]})
	g.node("phone").link("next", "check")
	check.link("case_1", "mark")
	check.link("else", "dial")
	_n(g, "mark", "effect", {"set_flags": ["called_today"], "deltas": {"A": 2}}).link("next", "ev")
	_n(g, "dial", "window_bubble").link("next", "fp")
	var pair := _free(g)
	var r: day_runner = pair[0]
	var host: FakeHost = pair[1]
	GameState.reset()
	r.click("phone")
	_eq("第一次走来电", host.log, ["ev"] as Array[String])
	_is_true("效果开了 flag", GameState.has_flag(&"called_today"))
	_eq("效果加了分", GameState.score_of(GameState.SCORE_A), 2)
	r.step_done()
	host.log.clear()
	r.click("phone")
	_eq("第二次走拨号盘", host.log, ["dial"] as Array[String])

	var fx := flow_node.new("fx", "effect")
	fx.props = {"if": "flag:never", "deltas": {"A": 5}}
	day_runner.apply_effect(fx)
	_eq("效果的条件不成立就不生效", GameState.score_of(GameState.SCORE_A), 2)
	fx.props = {"deltas": {"mails_read": 1}}
	day_runner.apply_effect(fx)
	day_runner.apply_effect(fx)
	_eq("计数器 +1 两次", GameState.var_of(&"mails_read"), 2)
	GameState.reset()


func _test_door() -> void:
	_section = "门"
	# 用 flag 代替 inbox_empty（这里没有收件箱）：门是瞬发判定，读状态。
	var g := _body()
	var door := _n(g, "door", "interactable", {"object": "door", "unlock": "", "repeat": true})
	g.node("fp").link("listen", "door", false)
	var check := _n(g, "door_check", "if", {"cases": [{"if": "flag:inbox_done"}]})
	door.link("next", "door_check")
	check.link("case_1", "out")
	check.link("else", "nag")
	_n(g, "nag", "story_bubble").link("next", "fp")
	var pair := _free(g)
	var r: day_runner = pair[0]
	var host: FakeHost = pair[1]
	host.waits = ["show_result"]
	GameState.reset()
	r.click("door")
	_eq("活没干完：提示一句，回自由环节", [host.log, r.mode], [["nag"] as Array[String], day_runner.FREE])
	GameState.set_flag(&"inbox_done")
	host.log.clear()
	r.click("door")
	_eq("干完了：下班结算", host.log, ["out", "res"] as Array[String])
	GameState.reset()


func _test_save_abort() -> void:
	_section = "读档"
	var pair := _free()
	var r: day_runner = pair[0]
	r.click("phone")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(r.save_data()))
	var back := day_runner.new()
	back.attach(_body(), FakeHost.new())
	back.load_data(saved)
	_eq("读回来停在桥段中间", [back.mode, back.current, back.hub], [day_runner.CHAIN, "ev", "fp"])
	back.abort_chain()
	_eq("退回链开始前的自由环节", [back.mode, back.current], [day_runner.FREE, "fp"])
	_is_true("退回之后照常能点", back.click("laptop"))


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
	print("\n============= day_runner_test =============")
	if _failed == 0:
		print("全部通过：%d 项" % _passed)
	else:
		print("通过 %d 项，失败 %d 项：" % [_passed, _failed])
		for line in _fail_lines:
			print(line)
	print("===========================================\n")
	get_tree().quit(1 if _failed > 0 else 0)
