extends Control
class_name clickable_item

## 通用可点击元件：
## 1. 有 ShaderMaterial 时，鼠标悬停自动开关 shader 的 enabled 参数（描边发光）。
## 2. 鼠标左键点击时，在 SignalBus 上发 object_clicked(节点名)。点了之后发生什么
##    （开窗、播桥段、下班……）由当天的天内图决定，这里不管。
##
## 两者都受回合状态管辖：只有上班时间（RoundState.is_interactive()）才响应。
## 发光也要一起锁——只拦点击不拦发光的话，剧情期间物件还会亮，看起来像能点。
##
## 直接把这个脚本挂到任意 Control（TextureRect / Panel / ...）上即可。
## **节点名就是物件 id**，和关卡里世界表 objects 的 id 对应（laptop / door / caller…）。

## 点击本节点时同时发出，需要就地处理时可以直接连这个。
signal clicked

var _pressed_inside := false
var _is_hovering := false


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	# 状态切换时鼠标可能正停在物件上，得主动把发光同步一次。
	SignalBus.round_state_change.connect(_on_round_state_change)
	SignalBus.interaction_lock_changed.connect(_on_round_state_change)


func _on_round_state_change(_rs) -> void:
	_set_glow(_is_hovering)


func _gui_input(event: InputEvent) -> void:
	if not RoundState.is_interactive():
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return

	if event.pressed:
		_pressed_inside = true
		accept_event()
	elif _pressed_inside:
		# 按下后拖到节点外再松开不算点击，和按钮的行为一致。
		_pressed_inside = false
		if Rect2(Vector2.ZERO, size).has_point(event.position):
			_emit_click()
		accept_event()


func _emit_click() -> void:
	clicked.emit()
	SignalBus.object_clicked.emit(StringName(name))


func _on_mouse_entered() -> void:
	_is_hovering = true
	_set_glow(true)


func _on_mouse_exited() -> void:
	_is_hovering = false
	_set_glow(false)


func _set_glow(on: bool) -> void:
	# 锁住的时候一律不亮，不管鼠标在哪。
	if not RoundState.is_interactive():
		on = false
	if material is ShaderMaterial:
		material.set_shader_parameter("enabled", on)
