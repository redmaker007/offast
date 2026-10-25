extends PanelContainer
class_name room_view

## 房间：开局按关卡世界表里的 objects 生成桌上 / 墙上的物件。
##
## 每个物件长成和原来手摆时一样的结构，节点名也一样（别处按路径找它们）：
##     Control/<id>_control           铺满房间的透明壳
##         <id>                       TextureRect + clickable_item（日历是 calendar_face）
##             HoverScale             悬停放大 + 音效（有 hover 才挂）
##             camera_focus           点击推近（有 camera 才挂）
##
## 物件记录的字段见 docs/level_engine.md 第 5 节。素材用 asset_library 找，玩家可以在外部文件夹盖掉。
## 挂在 main_scene 的 Control 节点上，_ready 时 round_manager 已经读好关卡了（它排在前面）。

const HOVER_SCENE := preload("res://addons/ui_polish/hover_scale.tscn")
const CALENDAR_FACE := preload("res://main_game/game/widgets/calendar_face.gd")
const CLICKABLE := preload("res://main_game/game/widgets/clickable_item.gd")
const CAMERA_FOCUS := preload("res://main_game/game/widgets/camera_focus.gd")

## 发光描边的 shader 和参数，所有物件一样。
const GLOW_SHADER := preload("res://theme/glow_outline.gdshader")
const GLOW_PARAMS := {
	"enabled": false,
	"maxLineWidth": 14.4990006887025,
	"minLineWidth": 0.0,
	"speed": 5.2950002515125,
	"blockSize": 20.0,
	"color": Color(0.98764473, 0.5664917, 0.48990333, 1),
	"tolerance": 0.606000028785,
}

## 日历四张图对应的剩余命数。
const FACE_SLOTS := {"3": "face_3_lives", "2": "face_2_lives", "1": "face_1_life", "0": "face_0_lives"}


func _ready() -> void:
	var level: level_runner = %round_manager.level
	if level == null or level.doc == null:
		return
	build(level.doc.world.get("objects", []))


## 按物件表生成（已经有的同名物件先拆掉，换关卡 / 测试重建时用）。
func build(objects: Array) -> void:
	for obj in objects:
		if obj is Dictionary and obj.has("texture"):
			var old := get_node_or_null(str(obj["id"]) + "_control")
			if old != null:
				remove_child(old)
				old.queue_free()
			_spawn(obj)


func _spawn(obj: Dictionary) -> void:
	var id := str(obj["id"])
	var wrap := Control.new()
	wrap.name = id + "_control"
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wrap)
	wrap.owner = owner

	var clickable := bool(obj.get("clickable", true))
	var n := TextureRect.new()
	n.name = id
	if obj.has("faces"):
		n.set_script(CALENDAR_FACE)
		for key in FACE_SLOTS:
			n.set(FACE_SLOTS[key], asset_library.texture(str(obj["faces"].get(key, ""))))
	elif clickable:
		n.set_script(CLICKABLE)
	n.texture = asset_library.texture(str(obj.get("texture", "")))
	n.z_index = int(obj.get("z", 0))
	n.mouse_filter = Control.MOUSE_FILTER_PASS if clickable else Control.MOUSE_FILTER_IGNORE
	if bool(obj.get("glow", false)):
		var m := ShaderMaterial.new()
		m.shader = GLOW_SHADER
		for p in GLOW_PARAMS:
			m.set_shader_parameter(p, GLOW_PARAMS[p])
		n.material = m

	# 先锚点后偏移，和场景文件里的顺序一样，不然偏移会被锚点换算掉。
	var a: Array = obj.get("anchors", [0, 0, 0, 0])
	n.anchor_left = a[0]
	n.anchor_top = a[1]
	n.anchor_right = a[2]
	n.anchor_bottom = a[3]
	var o: Array = obj.get("offsets", [0, 0, 0, 0])
	n.offset_left = o[0]
	n.offset_top = o[1]
	n.offset_right = o[2]
	n.offset_bottom = o[3]
	var grow: Array = obj.get("grow", [1, 1])
	n.grow_horizontal = int(grow[0])
	n.grow_vertical = int(grow[1])
	n.scale = _vec(obj.get("scale", [1, 1]))
	n.pivot_offset = _vec(obj.get("pivot", [0, 0]))

	wrap.add_child(n)
	n.owner = owner
	if id == "calendar":
		# 日历页按 %calendar 找它拿当前那张图。
		n.unique_name_in_owner = true
	if n.has_method("refresh"):
		# 日历 _ready 时还没有 owner、查不到命数，设好之后按真实命数再换一次图。
		n.refresh()

	var hover = obj.get("hover", null)
	if hover is Dictionary:
		var hs: Node = HOVER_SCENE.instantiate()
		hs.hover_scale = float(hover.get("scale", 1.08))
		hs.hover_volume = float(hover.get("volume", 1.0))
		hs.click_volume = float(hover.get("click_volume", 1.0))
		hs.center_pivot = bool(hover.get("center_pivot", true))
		if hover.has("hover_sound"):
			hs.hover_sound = asset_library.audio(str(hover["hover_sound"]))
		if hover.has("click_sound"):
			hs.click_sound = asset_library.audio(str(hover["click_sound"]))
		n.add_child(hs)
		hs.owner = owner

	var cam = obj.get("camera", null)
	if cam is Dictionary:
		var cf: Node = CAMERA_FOCUS.new()
		cf.name = "camera_focus"
		cf.zoom_scale = float(cam.get("zoom", 1.5))
		cf.duration = float(cam.get("duration", 0.4))
		cf.enabled = bool(cam.get("enabled", true))
		n.add_child(cf)
		cf.owner = owner


static func _vec(v: Variant) -> Vector2:
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO
