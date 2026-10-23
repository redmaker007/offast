extends Node

## 镜头聚焦（camera_focus）的自测。跑法见 tests/run_tests.ps1。
##
## 覆盖：场景里笔记本下面真的挂着、点笔记本推近且对准、弹窗不跟着放大、
## 关弹窗复原、补间最后到位、关掉 enabled 不响应、不开弹窗的物件点别处复原、
## 两个物件之间接管、场景退出时复原。
##
## 和真机一样把场景套在一层 CanvasLayer 里（SceneTransition 就是这么挂的），
## 镜头要是动的是 viewport 的 canvas_transform，在这层里就推不动。

const GAME_SCENE := "res://main_game/game/main_scene.tscn"
const LAPTOP := "Control/laptop_control/laptop"

var _passed := 0
var _failed := 0
var _fail_lines: Array[String] = []
var _section := ""

var _game: Node
var _layer: CanvasLayer


func _ready() -> void:
	_game = load(GAME_SCENE).instantiate()
	_layer = CanvasLayer.new()
	_layer.add_child(_game)
	get_tree().root.add_child.call_deferred(_layer)
	await get_tree().process_frame
	await get_tree().process_frame

	_test_wired_in_scene()
	await _test_click_opens_and_close_releases()
	await _test_tween_focus()
	_test_disabled_ignores_click()
	_test_click_elsewhere_releases()
	_test_second_takes_over()
	_test_exit_tree_resets()
	_report()


func _focus() -> camera_focus:
	return _game.get_node(LAPTOP + "/camera_focus") as camera_focus


func _laptop() -> clickable_item:
	return _game.get_node(LAPTOP) as clickable_item


func _screen_center() -> Vector2:
	return get_viewport().get_visible_rect().size / 2.0


func _room() -> Control:
	return _game.get_node("Control")


func _center_on_screen(c: Control) -> Vector2:
	return c.get_global_transform_with_canvas() * (c.size / 2.0)


func _room_at_rest() -> bool:
	return _room().position == Vector2.ZERO and _room().scale == Vector2.ONE


func _press_at(screen_pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = screen_pos
	ev.global_position = screen_pos
	get_viewport().push_input(ev, true)


func _test_wired_in_scene() -> void:
	_section = "场景接线"
	var f := _focus()
	_is_true("笔记本下面挂着 camera_focus", f != null)
	if f:
		_is_true("默认开着", f.enabled)
		_eq("自动找到的房间是 Control", f.view, _room())
		_is_true("房间一开始没被变换", _room_at_rest())
	_is_false("笔记本窗口不在房间里", _room().is_ancestor_of(_game.get_node("laptop_page")))


func _test_click_opens_and_close_releases() -> void:
	_section = "点击推近 / 关窗复原"
	var f := _focus()
	f.duration = 0.0
	f.zoom_scale = 2.0
	# clickable_item 被点时先发 clicked，再在 SignalBus 上发 open_laptop_request。
	_laptop().clicked.emit()
	SignalBus.open_laptop_request.emit()
	await get_tree().create_timer(0.4).timeout

	var page: Control = _game.get_node("laptop_page")
	_is_true("笔记本窗口开了", page.visible)
	_is_true("镜头在笔记本手里", f.is_focused())
	_near("笔记本中心落在屏幕中心", _center_on_screen(_laptop()), _screen_center())
	_near("放大倍数", _room().scale, Vector2(2, 2))
	_near("弹窗不跟着放大", page.get_global_transform_with_canvas().get_scale(), Vector2.ONE)

	WindowManager.close_current(_game)
	await get_tree().create_timer(0.4).timeout
	_is_false("窗口关掉了", page.visible)
	_is_false("镜头交出去了", f.is_focused())
	_is_true("关窗后复原", _room_at_rest())


func _test_tween_focus() -> void:
	_section = "补间"
	var f := _focus()
	f.duration = 0.2
	f.zoom_scale = 1.5
	f.focus()
	_eq("有补间时不会瞬间跳过去", _room().scale, Vector2.ONE)
	await get_tree().create_timer(0.3).timeout
	_near("补间结束后笔记本在屏幕中心", _center_on_screen(_laptop()), _screen_center())
	_near("补间结束后放大倍数", _room().scale, Vector2(1.5, 1.5))
	f.release()
	await get_tree().create_timer(0.3).timeout
	_near("补间拉远回原样", _room().position, Vector2.ZERO)


func _test_disabled_ignores_click() -> void:
	_section = "关掉 enabled"
	var f := _focus()
	f.duration = 0.0
	f.focus()
	f.enabled = false
	_is_true("关掉时正推着的镜头复原", _room_at_rest())
	_laptop().clicked.emit()
	_is_false("关着时点击不推近", f.is_focused())
	f.enabled = true


func _test_click_elsewhere_releases() -> void:
	_section = "点别处复原"
	var f := _focus()
	f.duration = 0.0
	_laptop().clicked.emit()
	_is_true("推近了", f.is_focused())
	_press_at(_center_on_screen(_laptop()))
	_is_true("点父节点自己不复原", f.is_focused())
	_press_at(Vector2(2, 2))
	_is_false("点别处复原", f.is_focused())
	_is_true("画面回原样", _room_at_rest())


func _test_second_takes_over() -> void:
	_section = "接管镜头"
	var first := _focus()
	first.duration = 0.0
	var notes: clickable_item = _game.get_node("Control/notes_control/notes")
	var second := camera_focus.new()
	second.duration = 0.0
	notes.add_child(second)

	_laptop().clicked.emit()
	notes.clicked.emit()
	_is_false("先推的交出镜头", first.is_focused())
	_is_true("后推的握着镜头", second.is_focused())
	_near("镜头对准后点的那个", _center_on_screen(notes), _screen_center())
	first.release()
	_is_true("先推的复原不会拉走别人的镜头", second.is_focused())

	second.release()
	_is_true("后推的复原回原样", _room_at_rest())
	notes.remove_child(second)
	second.free()


func _test_exit_tree_resets() -> void:
	_section = "场景退出"
	var f := _focus()
	f.duration = 0.0
	f.focus()
	get_tree().root.remove_child(_layer)
	_is_true("场景移出树时房间复原", _room_at_rest())
	_layer.free()


func _near(label: String, actual: Vector2, expected: Vector2) -> void:
	_record(label, actual.distance_to(expected) < 0.5, "实际 %s，期望 %s" % [actual, expected])


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
	print("\n============= camera_focus_test ===========")
	if _failed == 0:
		print("全部通过：%d 项" % _passed)
	else:
		print("通过 %d 项，失败 %d 项：" % [_passed, _failed])
		for line in _fail_lines:
			print(line)
	print("===========================================\n")
	get_tree().quit(1 if _failed > 0 else 0)
