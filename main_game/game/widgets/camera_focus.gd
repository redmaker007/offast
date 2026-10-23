extends Node
class_name camera_focus

## 镜头聚焦：挂在可互动的东西下面（clickable_item 物件 / Button 按钮），
## 玩家点了父节点，镜头就缓动推近、对准父节点的中心；离开时缓动复原。
##
## 「离开」= 这次点击打开的弹窗关掉了（WindowManager 报告这个场景一个窗口都没了）。
## 点了不开弹窗的物件，就等玩家在父节点以外的地方点一下（左右键都行）再复原。
##
## 没有用 Camera2D，也没动 viewport 的 canvas_transform：SceneTransition 把每个场景
## 套在自己的 CanvasLayer 里，canvas_transform 管不到那一层。这里是直接缩放 + 平移
## 「房间」那个 Control（view），弹窗和 HUD 不在房间里面，所以推近时不会跟着放大。
## 全场同一时间只会有一个 camera_focus 推着镜头，后推的接管。
##
## 直接把这个脚本挂到可互动节点下面的一个空 Node 上即可。

## 开着才响应点击。运行时关掉的话，正推着的镜头也会复原。
@export var enabled: bool = true:
	set(v):
		enabled = v
		if not v and is_inside_tree():
			release()

## 放大倍数，1 是不放大。
@export_range(1.0, 5.0, 0.05) var zoom_scale: float = 1.5

## 推近 / 拉远用的秒数，0 表示瞬间切过去。
@export_range(0.0, 2.0, 0.05) var duration: float = 0.4

## 推近时整体缩放的那个节点（房间）。留空就自动找：父节点往上、
## 直接挂在场景根下面的那个祖先——main_scene 里就是 Control。
@export var view: Control

## view 上记原始 position / scale 用的 meta，复原时回到这里。
const REST_META := &"camera_focus_rest"

## 当前握着镜头的那个 camera_focus，和它正在跑的补间。
static var _owner: camera_focus
static var _tween: Tween


func _ready() -> void:
	var p := get_parent()
	if p is clickable_item:
		p.clicked.connect(_on_parent_clicked)
	elif p is BaseButton:
		p.pressed.connect(_on_parent_clicked)
	else:
		push_warning("camera_focus 要挂在 clickable_item 或 Button 下面（节点：%s）" % get_path())
	if view == null:
		view = _find_view()
	WindowManager.popup_state_changed.connect(_on_popup_state_changed)


func _exit_tree() -> void:
	# 场景被切走（SceneTransition 挂起也算）时直接摆回原样，回来时不会停在放大的样子。
	if _owner == self:
		_owner = null
		if _tween:
			_tween.kill()
		if view and view.has_meta(REST_META):
			var rest: Array = view.get_meta(REST_META)
			view.position = rest[0]
			view.scale = rest[1]


## 推近到父节点。点击父节点时自动调用，代码里也可以直接调。
func focus() -> void:
	if view == null:
		return
	if not view.has_meta(REST_META):
		view.set_meta(REST_META, [view.position, view.scale])
	# 别人握着镜头也直接接管：从现在的样子补间到这边，不先拉回原样。
	_owner = self
	var rest: Array = view.get_meta(REST_META)
	var s: Vector2 = rest[1] * zoom_scale
	_move_to(_focus_position(s), s)


## 复原镜头。镜头不在自己手里时什么都不做，不会把别人的镜头拉回去。
func release() -> void:
	if _owner != self:
		return
	_owner = null
	var rest: Array = view.get_meta(REST_META)
	_move_to(rest[0], rest[1])


func is_focused() -> bool:
	return _owner == self


func _on_parent_clicked() -> void:
	if enabled:
		focus()


func _on_popup_state_changed(scene_root: Node, has_window: bool) -> void:
	if not has_window and scene_root == _scene_root():
		release()


## 用 _input 而不是 _unhandled_input：点到别的物件时点击会被它吃掉，
## 那样就收不到「点了别处」。
func _input(event: InputEvent) -> void:
	if not is_focused():
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	# 有弹窗开着就等它关，点弹窗外面不算离开。
	if WindowManager.get_current(_scene_root()):
		return
	var p := get_parent()
	if p is Control:
		# 事件坐标是屏幕上的，要连房间的缩放一起逆回去才是父节点的本地坐标。
		var local: Vector2 = p.get_global_transform_with_canvas().affine_inverse() * event.position
		if Rect2(Vector2.ZERO, p.size).has_point(local):
			return
	release()


## 所在场景的根。存在场景里的节点 owner 就是它；运行时 add_child 出来的没有 owner，
## 就借父节点的。
func _scene_root() -> Node:
	return owner if owner else get_parent().owner


func _find_view() -> Control:
	var root := _scene_root()
	var n := get_parent()
	while n and n.get_parent() != root:
		n = n.get_parent()
	if n is Control:
		return n
	push_warning("camera_focus 找不到要缩放的房间节点，请手动填 view（节点：%s）" % get_path())
	return null


## view 放大到 s 倍时，要把父节点中心摆到屏幕中心，view 的 position 该是多少。
func _focus_position(s: Vector2) -> Vector2:
	var p := get_parent()
	var target_g: Vector2 = p.global_position
	if p is Control:
		# 用全局变换算中心，父节点自己的 scale / pivot 都算进去。
		target_g = p.get_global_transform() * (p.size / 2.0)
	# 换到 view 自己的坐标里，和 view 现在缩放了多少无关。
	var target := view.get_global_transform().affine_inverse() * target_g
	# 屏幕中心换到 view 父节点的坐标里（带上 SceneTransition 那层 CanvasLayer）。
	var screen_center := get_viewport().get_visible_rect().size / 2.0
	var center := (view.get_parent() as CanvasItem).get_global_transform_with_canvas().affine_inverse() * screen_center
	# Control 的变换绕 pivot_offset 缩放：父坐标 = position + pivot + s * (本地 - pivot)。
	var pivot := view.pivot_offset
	return center - pivot - s * (target - pivot)


func _move_to(pos: Vector2, s: Vector2) -> void:
	if _tween:
		_tween.kill()
	if duration <= 0.0:
		view.position = pos
		view.scale = s
		return
	_tween = view.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(view, "position", pos, duration)
	_tween.parallel().tween_property(view, "scale", s, duration)
