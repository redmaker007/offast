extends Control

## 通用可点击元件：
## 1. 有 ShaderMaterial 时，鼠标悬停自动开关 shader 的 enabled 参数（描边发光）。
## 2. 鼠标左键点击时，在 SignalBus 上发出 click_signal 指定的信号。
##
## 直接把这个脚本挂到任意 Control（TextureRect / Panel / ...）上即可。

## 点击本节点时同时发出，需要就地处理时可以直接连这个。
signal clicked

## 点击时要在 SignalBus 上发出的信号名，填 signal_bus.gd 里声明的无参数信号。
## 留空表示不发信号（只做悬停发光）。名字打错时运行到点击那一刻会 push_error。
@export var click_signal:String

var _pressed_inside := false


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _gui_input(event: InputEvent) -> void:
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
	if click_signal.is_empty():
		return
	if not SignalBus.has_signal(click_signal):
		push_error("SignalBus 上没有名为 \"%s\" 的信号（节点：%s）" % [click_signal, name])
		return
	SignalBus.emit_signal(click_signal)


func _on_mouse_entered() -> void:
	_set_glow(true)


func _on_mouse_exited() -> void:
	_set_glow(false)


func _set_glow(on: bool) -> void:
	if material is ShaderMaterial:
		material.set_shader_parameter("enabled", on)
