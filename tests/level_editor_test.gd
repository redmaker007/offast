extends Node

## GM 关卡编辑器 4a（外层画布）的自测。跑法见 tests/run_tests.ps1。
##
## 编辑操作都有对应的方法（add_node / link / delete_node …），界面上的拖拽、点按钮最后也是调它们，
## 这里直接调方法，再核对内存里的关卡、画布上的节点和连线、错误列表。

const EDITOR_SCENE := "res://main_game/editor/level_editor.tscn"
const MENU_SCENE := "res://main_game/menu/menu_scene.tscn"
const TEST_LEVEL := "__editor_test"

var _passed := 0
var _failed := 0
var _fail_lines: Array[String] = []
var _section := ""

var _ed: level_editor


func _ready() -> void:
	_ed = load(EDITOR_SCENE).instantiate()
	_ed.level_name = TEST_LEVEL
	add_child(_ed)
	await get_tree().process_frame

	_test_open()
	_test_add_and_link()
	_test_brancher_cases()
	_test_delete_and_role()
	_test_errors_panel()
	_test_save_reload()
	await _test_menu_entry()
	_report()


func _fresh() -> void:
	_ed.load_doc(level_converter.from_story_dir())


func _graph_nodes() -> Array:
	return _ed._graph.get_children().filter(func(c): return c is GraphNode)


func _codes() -> Array:
	return _ed.errors.map(func(e): return "%s@%s" % [e.code, e.location()])


func _test_open() -> void:
	_section = "打开"
	_is_true("没有存档时开一份空关卡", _ed.doc != null)
	_fresh()
	_eq("现有关卡没有错误", _ed.errors.size(), 0)
	_eq("画布上每个外层节点一个框", _graph_nodes().size(), _ed.doc.graph.nodes.size())
	var links := 0
	for id in _ed.doc.graph.nodes:
		var n: flow_node = _ed.doc.graph.nodes[id]
		for port in n.outs:
			links += n.targets(port).size()
	_eq("每条线都画出来了", _ed._graph.get_connection_list().size(), links)
	_eq("错误列表显示没有错误", _ed._error_list.get_item_text(0), "没有错误，可以跑")
	_is_false("刚打开不算有改动", _ed.dirty)


func _test_add_and_link() -> void:
	_section = "新建 / 连线"
	_fresh()
	var id := _ed.add_node("day", Vector2(100, 300))
	_eq("新天节点的 id", id, "day_6")
	_is_true("画布上多了一个框", _ed._graph.has_node(NodePath(id)))
	_is_true("有改动了", _ed.dirty)
	_is_true("新节点没人连过来：孤立", "UNREACHABLE@day_6" in _codes(), str(_codes()))
	_is_true("新节点没接出口", "PORT_MISSING@day_6" in _codes(), str(_codes()))
	_eq("属性面板换成新节点", _ed.selected, id)

	# 插到第 5 天和结局分化器之间。
	_ed.link("day_5", 0, id)
	_ed.link(id, 0, "ending_branch")
	_eq("插进去之后没有错误", _codes(), [])
	_eq("第 5 天的出口换成了新节点（单出口先拆旧线）", _ed.doc.graph.node("day_5").targets("next"), [id] as Array[String])

	_ed.unlink(id, 0, "ending_branch")
	_is_true("拆线后又缺出口", "PORT_MISSING@day_6" in _codes())


func _test_brancher_cases() -> void:
	_section = "分化器条件"
	_fresh()
	var br := _ed.add_node("brancher")
	_ed.add_case(br)
	_ed.add_case(br)
	var n := _ed.doc.graph.node(br)
	_eq("两条条件", node_types.branch_cases(n).size(), 2)
	_eq("画布上的框有 3 个出口（2 条件 + else）", (_ed._graph.get_node(NodePath(br)) as GraphNode).get_output_port_count(), 3)
	_ed.link(br, 0, "end_A")
	_ed.link(br, 1, "end_B")
	_ed.link(br, 2, "end_C")
	_ed.set_prop(br, "cases", [{"if": "flag:x"}, {"if": "flag:y"}], true)
	_ed.remove_case(br, 0)
	_eq("删掉第 1 条后只剩一条", node_types.branch_cases(n), [{"if": "flag:y"}])
	_eq("原来第 2 条的线挪到第 1 个出口", n.targets("case_1"), ["end_B"] as Array[String])
	_is_false("多出来的出口没了", n.outs.has("case_2"))
	_eq("else 不动", n.targets("else"), ["end_C"] as Array[String])


func _test_delete_and_role() -> void:
	_section = "删节点 / 改类型"
	_fresh()
	_ed.delete_node("day_3")
	_is_false("节点没了", _ed.doc.graph.has("day_3"))
	_is_false("画布上的框也没了", _ed._graph.has_node(NodePath("day_3")))
	_eq("指向它的线跟着拆掉", _ed.doc.graph.node("day_2").targets("next"), [] as Array[String])
	_is_true("第 2 天缺出口", "PORT_MISSING@day_2" in _codes())

	_fresh()
	_ed.set_prop("day_5", "role", "ending", true)
	_is_true("改成结局天", str(_ed.doc.graph.node("day_5").props["role"]) == "ending")
	_ed.doc.graph.node("day_5").outs.clear()
	_ed.set_prop("day_5", "ending", "C", true)
	_is_true("结局分化器没人连了：孤立", "UNREACHABLE@ending_branch" in _codes(), str(_codes()))


func _test_errors_panel() -> void:
	_section = "错误列表"
	_fresh()
	_ed.doc.graph.node("day_2").body.node("door").props["object"] = "toaster"
	_ed.load_doc(_ed.doc)
	_eq("列出天内的错误", _ed._error_list.item_count, 1)
	var e: level_error = _ed._error_list.get_item_metadata(0)
	_eq("天内的错误落在它所在的天节点上", _ed.error_target(e), "day_2")
	_ed._on_error_selected(0)
	_eq("点错误跳到那个节点", _ed.selected, "day_2")
	var gn := _ed._graph.get_node(NodePath("day_2")) as GraphNode
	_eq("出错的框标红", gn.self_modulate, level_editor.ERROR_TINT)


func _test_save_reload() -> void:
	_section = "保存 / 重新读取"
	_fresh()
	_ed.add_node("jumper", Vector2(40, 40))
	_eq("保存成功", _ed.save(), "")
	_is_false("保存后不算有改动", _ed.dirty)
	_ed.load_doc(level_doc.create())
	_ed.reload()
	_is_true("重新读取拿回刚存的", _ed.doc.graph.has("jumper_1"))
	_eq("位置也存住了", _ed.doc.graph.node("jumper_1").pos, Vector2(40, 40))
	DirAccess.remove_absolute(level_store.USER_DIR + TEST_LEVEL + level_store.EXT)


func _test_menu_entry() -> void:
	_section = "菜单入口"
	var was: bool = LocaleSettings.gm_mode
	LocaleSettings.gm_mode = false
	var menu: Node = load(MENU_SCENE).instantiate()
	add_child(menu)
	await get_tree().process_frame
	_is_false("GM 模式关着没有编辑器按钮", menu.has_node("background/VBoxContainer/editor_button"))
	menu.queue_free()
	await get_tree().process_frame

	LocaleSettings.gm_mode = true
	menu = load(MENU_SCENE).instantiate()
	add_child(menu)
	await get_tree().process_frame
	var b := menu.get_node_or_null("background/VBoxContainer/editor_button")
	_is_true("GM 模式开着有编辑器按钮", b != null)
	if b:
		var box: Node = b.get_parent()
		_eq("排在退出前面", b.get_index() + 1, box.get_node("quit_button").get_index())
	menu.queue_free()
	LocaleSettings.gm_mode = was


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
	print("\n============ level_editor_test ============")
	if _failed == 0:
		print("全部通过：%d 项" % _passed)
	else:
		print("通过 %d 项，失败 %d 项：" % [_passed, _failed])
		for line in _fail_lines:
			print(line)
	print("===========================================\n")
	get_tree().quit(1 if _failed > 0 else 0)
