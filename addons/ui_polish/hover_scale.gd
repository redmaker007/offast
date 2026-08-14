extends Node

## 鼠标悬停时放大到的倍数。
@export var hover_scale: float = 1.08

## 放大/复原动画时长（秒）。
@export var tween_duration: float = 0.15

## 悬停音效素材，在 Inspector 里拖入音频文件。
@export var hover_sound: AudioStream

## 悬停音效音量。
@export_range(0.0, 1.0, 0.01) var hover_volume: float = 1.0

## 按下时缩小到的倍数。
@export var press_scale: float = 0.92

## 按下/松开动画时长（秒）。
@export var press_tween_duration: float = 0.08

## 点击音效素材，在 Inspector 里拖入音频文件（留空则不播放）。
@export var click_sound: AudioStream

## 点击音效音量。
@export_range(0.0, 1.0, 0.01) var click_volume: float = 1.0

## 是否把父节点的 pivot 设到正中，让缩放和歪头以中心为原点。
## 父节点本身带着非 1 的 scale 时，改 pivot 会让它的显示位置平移，
## 这种情况要么关掉这个开关，要么改成用矩形尺寸而不是 scale 来控制大小。
@export var center_pivot: bool = true

var target: Control
var hover_audio_player: AudioStreamPlayer
var click_audio_player: AudioStreamPlayer
var _is_hovering := false
var _scale_tween: Tween
## 父节点原本的 scale，所有动画以它为基准，避免覆盖掉场景里设好的缩放。
var _base_scale := Vector2.ONE


func _ready() -> void:
	var parent := get_parent()
	if parent is not Control:
		push_error("HoverScale 的父节点必须是 Control（当前：%s）" % parent)
		return

	target = parent as Control
	_base_scale = target.scale
	_apply_pivot()
	target.resized.connect(_apply_pivot)
	target.mouse_entered.connect(_on_mouse_entered)
	target.mouse_exited.connect(_on_mouse_exited)

	if target is BaseButton:
		# 按钮走自己的信号，这样键盘/焦点触发的按下也有动画。
		target.button_down.connect(_on_press_start)
		target.button_up.connect(_on_button_up)
	else:
		# 其它 Control 自己从鼠标事件里认按下和松开。
		# gui_input 信号比 _gui_input() 虚函数先派发，所以父节点脚本里
		# 再 accept_event() 也不会影响这里收事件。
		target.gui_input.connect(_on_target_gui_input)

	hover_audio_player = AudioStreamPlayer.new()
	add_child(hover_audio_player)

	click_audio_player = AudioStreamPlayer.new()
	add_child(click_audio_player)


func _apply_pivot() -> void:
	if center_pivot:
		target.pivot_offset = target.size / 2.0


func _on_mouse_entered() -> void:
	_is_hovering = true
	_tween_scale(hover_scale, tween_duration)
	if hover_sound:
		hover_audio_player.stream = hover_sound
		hover_audio_player.volume_db = linear_to_db(maxf(hover_volume, 0.0001))
		hover_audio_player.play()


func _on_mouse_exited() -> void:
	_is_hovering = false
	_tween_scale(1.0, tween_duration)


func _on_target_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		_on_press_start()
	else:
		# 按住拖出去再松开时 mouse_exited 不会触发（按下期间悬停被锁在本节点上），
		# 所以这里按松开位置判断该回到哪个大小。
		_on_press_end(Rect2(Vector2.ZERO, target.size).has_point(event.position))


func _on_press_start() -> void:
	_tween_scale(press_scale, press_tween_duration)
	if click_sound:
		click_audio_player.stream = click_sound
		click_audio_player.volume_db = linear_to_db(maxf(click_volume, 0.0001))
		click_audio_player.play()


func _on_button_up() -> void:
	_on_press_end(_is_hovering)


func _on_press_end(is_over: bool) -> void:
	_tween_scale(hover_scale if is_over else 1.0, press_tween_duration)


func _tween_scale(target_scale: float, duration: float) -> void:
	if _scale_tween:
		_scale_tween.kill()

	# 当前相对基准的倍数，用来衡量这次变化幅度，决定歪头角度。
	var current_factor := 1.0
	if _base_scale.x != 0.0 and target.scale.x != 0.0:
		current_factor = target.scale.x / _base_scale.x
	var scale_ratio := target_scale / current_factor

	_scale_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_scale_tween.tween_property(target, "scale:x", _base_scale.x * target_scale, duration)
	_scale_tween.parallel().tween_property(target, "scale:y", _base_scale.y * target_scale, duration + 0.15)
	_scale_tween.parallel().tween_property(target, "rotation_degrees", 5.0 * scale_ratio * [-1.0, 1.0].pick_random(), 0.1)
	_scale_tween.parallel().tween_property(target, "rotation_degrees", 0.0, 0.1).set_delay(0.1)
