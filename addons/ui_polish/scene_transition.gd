extends Node

## 场景路由器 + 转场动画（autoload SceneTransition）。
##
## 和 get_tree().change_scene_to_file() 的区别：路由器自己持有场景实例，
## 每个场景套一层它自己的 CanvasLayer。这带来两件事——
##
##   1. 滑动转场成为可能。change_scene 是"先销毁旧的再建新的"，中间没有任何
##      一帧两个场景共存，所以它只能做淡入淡出；要滑动就必须两个同时在场。
##   2. 场景可以只挂起不销毁，当局数据原样留着，切回来接着玩，
##      不需要为每个字段写搬运代码。
##
## 为什么要额外套一层 CanvasLayer：CanvasLayer 的变换不继承父节点，所以移动
## 场景根节点是推不动画面的。把场景挂在我们自己的 CanvasLayer 上，动这一层的
## offset 才能整体滑动。
##
## 契约：被路由的场景不要自带 CanvasLayer——自带的那层同样不继承包装层的变换，
## 转场时不会跟着滑动。检测到会 push_warning 提醒。
##
## 用法：
##     SceneTransition.goto(MENU, SceneTransition.Slide.RIGHT, true)   # 挂起当前场景
##     SceneTransition.goto(GAME, SceneTransition.Slide.LEFT)          # 销毁当前场景
##     SceneTransition.has_retained(GAME)   # 有没有挂起的实例可以恢复
##     SceneTransition.discard(GAME)        # 丢掉挂起的实例（重开一局）

## NONE 立刻切换；FADE 黑幕淡入淡出；其余四个是滑动方向，
## 指的是"画面整体往哪边移动"——LEFT 就是新场景从右边推进来。
enum Slide { NONE, FADE, LEFT, RIGHT, UP, DOWN }

## 滑动转场时长（秒）。
@export var slide_duration: float = 0.35

## 黑幕淡入淡出的时长（秒）。
@export var fade_duration: float = 0.25

## 转场遮罩颜色。
@export var fade_color: Color = Color.BLACK

## 遮罩层的 layer，要盖在所有场景之上。
const OVERLAY_LAYER := 100
## 场景包装层的 layer。
const SCENE_LAYER := 0

## 转场彻底结束时发（旧场景已经挂起或销毁）。
signal transition_finished(path: String)

## 当前显示的场景，以及它的场景文件路径。
var current_scene: Node = null
var current_path: String = ""

var _current_layer: CanvasLayer = null
## path -> {"scene": Node, "layer": CanvasLayer}，挂起但没销毁的场景。
var _retained: Dictionary = {}
var _overlay_layer: CanvasLayer
var _overlay: ColorRect
var _busy := false


func _ready() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = OVERLAY_LAYER
	add_child(_overlay_layer)

	_overlay = ColorRect.new()
	_overlay.color = fade_color
	_overlay.color.a = 0.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay_layer.add_child(_overlay)


## 切到指定场景（传路径字符串或 PackedScene）。可以 await，转场播完才返回。
##
## retain_current 为 true 时，当前场景不销毁，只挂起（进程停掉、隐藏），
## 下次再 goto 回来时原样恢复。目标场景之前挂起过就复用那个实例，否则新实例化。
func goto(scene: Variant, slide := Slide.LEFT, retain_current := false) -> void:
	var path := _path_of(scene)
	if path.is_empty():
		push_error("SceneTransition.goto 需要场景路径或有 resource_path 的 PackedScene")
		return
	if _busy:
		push_warning("上一次转场还没结束，忽略这次 goto：%s" % path)
		return
	if path == current_path:
		return

	_busy = true
	_block_input(true)

	var outgoing_scene := current_scene
	var outgoing_layer := _current_layer
	var outgoing_path := current_path

	# 挂起登记要放在动画之前：新场景的 _ready 在这一轮就会跑，它可能马上
	# 就要问 has_retained()（比如菜单靠这个决定「继续游戏」能不能点）。
	if retain_current and outgoing_layer != null:
		if outgoing_scene.has_method("_scene_suspended"):
			outgoing_scene._scene_suspended()
		_retained[outgoing_path] = {"scene": outgoing_scene, "layer": outgoing_layer}

	var from_retained := _retained.has(path)
	var incoming_scene: Node
	var incoming_layer: CanvasLayer

	if from_retained:
		var kept: Dictionary = _retained[path]
		_retained.erase(path)
		incoming_scene = kept["scene"]
		incoming_layer = kept["layer"]
		incoming_layer.visible = true
		incoming_scene.process_mode = Node.PROCESS_MODE_INHERIT
	else:
		incoming_scene = _instantiate(scene, path)
		if incoming_scene == null:
			_block_input(false)
			_busy = false
			return
		incoming_layer = CanvasLayer.new()
		incoming_layer.layer = SCENE_LAYER
		incoming_layer.add_child(incoming_scene)
		add_child(incoming_layer)

	current_scene = incoming_scene
	current_path = path
	_current_layer = incoming_layer

	if from_retained and incoming_scene.has_method("_scene_resumed"):
		incoming_scene._scene_resumed()

	await _animate(outgoing_layer, incoming_layer, slide)

	if outgoing_layer != null:
		if retain_current:
			outgoing_layer.visible = false
			outgoing_layer.offset = Vector2.ZERO
			outgoing_scene.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			outgoing_layer.queue_free()

	_block_input(false)
	_busy = false
	transition_finished.emit(path)


## 这个场景有没有挂起的实例可以恢复。
func has_retained(path: String) -> bool:
	return _retained.has(path)


## 丢掉挂起的实例（比如「开始新游戏」要抛弃上一局）。当前正在显示的场景不受影响。
func discard(path: String) -> void:
	if not _retained.has(path):
		return
	var kept: Dictionary = _retained[path]
	_retained.erase(path)
	kept["layer"].queue_free()


## 丢掉所有挂起的实例。
func clear_retained() -> void:
	for path in _retained.keys():
		_retained[path]["layer"].queue_free()
	_retained.clear()


## 旧 API，保留兼容：带黑幕淡入淡出切场景，不挂起。
func goto_scene(path: String) -> void:
	await goto(path, Slide.FADE)


## 旧 API，保留兼容。
func goto_packed(packed_scene: PackedScene) -> void:
	await goto(packed_scene, Slide.FADE)


func _path_of(scene: Variant) -> String:
	if scene is PackedScene:
		return (scene as PackedScene).resource_path
	return str(scene)


func _instantiate(scene: Variant, path: String) -> Node:
	# 这里不能写 scene as PackedScene：传进来的是路径字符串时，
	# as 对非对象类型是直接抛错，不是返回 null。
	var packed: PackedScene
	if scene is PackedScene:
		packed = scene
	else:
		if not ResourceLoader.exists(path):
			push_error("场景不存在：%s" % path)
			return null
		packed = load(path)
	var node := packed.instantiate()
	_warn_if_canvas_layer(node, node, path)
	return node


func _warn_if_canvas_layer(node: Node, root: Node, path: String) -> void:
	for child in node.get_children():
		if child is CanvasLayer:
			push_warning(
				"场景 %s 自带 CanvasLayer（%s）。CanvasLayer 的变换不继承父节点，"
				% [path, root.get_path_to(child)]
				+ "这一层不会跟着转场一起滑动——把内容挪到场景根下面。"
			)
			continue
		_warn_if_canvas_layer(child, root, path)


func _animate(out_layer: CanvasLayer, in_layer: CanvasLayer, slide: Slide) -> void:
	match slide:
		Slide.NONE:
			if out_layer != null:
				out_layer.visible = false
			return
		Slide.FADE:
			await _fade_swap(out_layer, in_layer)
			return

	var vp := get_viewport().get_visible_rect().size
	# 新场景从 dir 那一侧进来，旧场景往反方向出去。
	var dir := _slide_vector(slide)
	in_layer.offset = dir * vp

	var tw := create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(in_layer, "offset", Vector2.ZERO, slide_duration)
	if out_layer != null:
		tw.parallel().tween_property(out_layer, "offset", -dir * vp, slide_duration)

	# 用计时器而不是 tween.finished：tween 被 kill 时不发 finished，await 那头会永久卡死。
	await get_tree().create_timer(slide_duration).timeout


func _slide_vector(slide: Slide) -> Vector2:
	match slide:
		Slide.LEFT:
			return Vector2.RIGHT
		Slide.RIGHT:
			return Vector2.LEFT
		Slide.UP:
			return Vector2.DOWN
		Slide.DOWN:
			return Vector2.UP
	return Vector2.ZERO


func _fade_swap(out_layer: CanvasLayer, in_layer: CanvasLayer) -> void:
	in_layer.visible = false
	await _fade_out()
	if out_layer != null:
		out_layer.visible = false
	in_layer.visible = true
	await _fade_in()


func _fade_out() -> void:
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", 1.0, fade_duration)
	await get_tree().create_timer(fade_duration).timeout


func _fade_in() -> void:
	var tw := create_tween()
	tw.tween_property(_overlay, "color:a", 0.0, fade_duration)
	await get_tree().create_timer(fade_duration).timeout


func _block_input(on: bool) -> void:
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
