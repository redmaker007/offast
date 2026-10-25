extends Node

## 房间数据化（第 3 阶段）的自测：按关卡世界表生成物件、外部素材文件夹覆盖。跑法见 tests/run_tests.ps1。
##
## 物件原来是 main_scene 里手摆的，现在由 room_view 开局时照数据生成——
## 这里核对生成出来的和数据一致，以及节点结构、名字和原来一样（别处按路径找它们）。

const GAME_SCENE := "res://main_game/game/main_scene.tscn"
const OVERRIDE_ID := "theme/items/2t.png"

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

	_test_built_from_data()
	await _test_click_through_graph()
	_test_external_override()
	_report()


func _objects() -> Array:
	return _game.get_node("%round_manager").level.doc.world["objects"]


func _test_built_from_data() -> void:
	_section = "按数据生成"
	var room := _game.get_node("Control")
	_is_true("房间挂着 room_view", room is room_view)
	for o in _objects():
		var id: String = o["id"]
		var n := room.get_node_or_null("%s_control/%s" % [id, id]) as TextureRect
		_is_true("生成了 %s" % id, n != null)
		if n == null:
			continue
		if not o.has("faces"):
			_eq("%s 的贴图" % id, n.texture.resource_path, "res://" + str(o["texture"]))
		_eq("%s 的层级" % id, n.z_index, int(o["z"]))
		_eq("%s 的缩放" % id, n.scale, Vector2(o["scale"][0], o["scale"][1]))
		_eq("%s 的左上偏移" % id, Vector2(n.offset_left, n.offset_top), Vector2(o["offsets"][0], o["offsets"][1]))
		var as_node: Node = n
		_eq("%s 能不能点" % id, as_node is clickable_item, bool(o["clickable"]))
		_eq("%s 发不发光" % id, n.material != null, bool(o["glow"]))
		_eq("%s 有没有悬停效果" % id, n.has_node("HoverScale"), o.has("hover"))
		_eq("%s 有没有镜头聚焦" % id, n.has_node("camera_focus"), o.has("camera"))

	var cal := _game.get_node_or_null("%calendar")
	_is_true("日历还能用 %calendar 找到", cal is calendar_face)
	if cal:
		_eq("日历按满命显示第一张", cal.texture.resource_path, "res://theme/items/calendar/1.png")
	var cf := room.get_node_or_null("laptop_control/laptop/camera_focus") as camera_focus
	_is_true("电脑的镜头聚焦找到了房间", cf != null and cf.view == room)


func _test_click_through_graph() -> void:
	_section = "点物件"
	SignalBus.story_finished.emit()
	await get_tree().process_frame
	var laptop: clickable_item = _game.get_node("Control/laptop_control/laptop")
	laptop.clicked.emit()
	SignalBus.object_clicked.emit(&"laptop")
	await get_tree().create_timer(0.5).timeout
	_is_true("点生成出来的电脑，照图打开电脑窗口", _game.get_node("laptop_page").visible)


func _test_external_override() -> void:
	_section = "外部素材覆盖"
	var dir := asset_library.USER_DIR.path_join(OVERRIDE_ID.get_base_dir())
	DirAccess.make_dir_recursive_absolute(dir)
	var path := asset_library.USER_DIR.path_join(OVERRIDE_ID)
	var img := Image.create(7, 5, false, Image.FORMAT_RGBA8)
	img.fill(Color.MAGENTA)
	img.save_png(path)
	asset_library.clear_cache()

	_eq("外部文件夹里找得到", asset_library.external_path(OVERRIDE_ID), path)
	var tex := asset_library.texture(OVERRIDE_ID)
	_eq("读的是外部那张", tex.get_size() if tex else Vector2.ZERO, Vector2(7, 5))

	var room: room_view = _game.get_node("Control")
	room.build(_objects())
	var n := room.get_node("laptop_control/laptop") as TextureRect
	_eq("重建房间后电脑换成了外部的图", n.texture.get_size(), Vector2(7, 5))

	DirAccess.remove_absolute(path)
	asset_library.clear_cache()
	_eq("删掉外部文件后退回自带的", asset_library.texture(OVERRIDE_ID).resource_path, "res://" + OVERRIDE_ID)
	_is_true("找不到的素材 exists 为假", not asset_library.exists("theme/items/nope.png"))


func _eq(label: String, actual: Variant, expected: Variant) -> void:
	_record(label, actual == expected, "实际 %s，期望 %s" % [actual, expected])


func _is_true(label: String, cond: bool, detail := "") -> void:
	_record(label, cond, "期望为真" if detail.is_empty() else detail)


func _record(label: String, ok: bool, detail: String) -> void:
	if ok:
		_passed += 1
		return
	_failed += 1
	_fail_lines.append("  ✗ [%s] %s —— %s" % [_section, label, detail])


func _report() -> void:
	print("\n============== room_view_test =============")
	if _failed == 0:
		print("全部通过：%d 项" % _passed)
	else:
		print("通过 %d 项，失败 %d 项：" % [_passed, _failed])
		for line in _fail_lines:
			print(line)
	print("===========================================\n")
	get_tree().quit(1 if _failed > 0 else 0)
