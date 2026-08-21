extends popup_window

## 设置面板。开关动画全部来自 popup_window，这里只管音量滑块、语言和关闭按钮。
##
## 滑块不直接动 AudioServer，一律走 AudioSettings——音量落在音频总线上，
## 存盘也归它，这里只负责「把玩家拖的值递过去」和「把当前值显示出来」。
##
## 关闭要走 WindowManager 而不是直接 close()：管理器记着「这个场景当前开着谁」，
## 绕过它直接关掉的话，下次 open_window() 会以为面板还开着，直接跳过不弹。

## 一行一条总线。加新的一行：场景里照 bgm_row 摆一份，再往这里登记一条。
var _rows: Array[Dictionary] = []


func _ready() -> void:
	super()
	_rows = [
		{"bus": AudioSettings.MUSIC, "slider": %bgm_slider, "label": %bgm_value},
		{"bus": AudioSettings.SFX, "slider": %sfx_slider, "label": %sfx_value},
	]
	for row in _rows:
		var slider: Slider = row["slider"]
		slider.value_changed.connect(_on_slider_changed.bind(row))
		slider.drag_ended.connect(_on_drag_ended)

	# 别的地方改了音量（reset()、以后可能加的快捷键），滑块要跟着动。
	AudioSettings.volume_changed.connect(_on_volume_changed)
	SignalBus.locale_changed.connect(_on_locale_changed)
	_pull_from_settings()
	_show_language()


## 把 AudioSettings 里的当前值摆到滑块上。
func _pull_from_settings() -> void:
	for row in _rows:
		_show(row, AudioSettings.get_volume(row["bus"]))


## 语言按钮按一下换下一种。按钮上显示的是**那个语言自己的写法**（中文 / English），
## 所以它不跟着 tr() 走（场景里关掉了自动翻译）。
func _on_language_pressed() -> void:
	LocaleSettings.next_locale()


func _on_locale_changed(_loc: String) -> void:
	_show_language()


func _show_language() -> void:
	%language_button.text = LocaleSettings.label_of()


func _on_slider_changed(value: float, row: Dictionary) -> void:
	# 拖动过程中每帧都写盘太浪费，先只应用，松手时再存。
	AudioSettings.set_volume(row["bus"], value, false)
	row["label"].text = _percent(value)


func _on_drag_ended(value_changed: bool) -> void:
	if value_changed:
		AudioSettings.save_settings()


func _on_volume_changed(bus: StringName, linear: float) -> void:
	for row in _rows:
		if row["bus"] == bus:
			_show(row, linear)


## 只更新显示，不回写——set_value_no_signal 免得又触发一轮 value_changed。
func _show(row: Dictionary, value: float) -> void:
	row["slider"].set_value_no_signal(value)
	row["label"].text = _percent(value)


func _percent(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)


func _on_close_pressed() -> void:
	# 用键盘拖滑块不会发 drag_ended，关面板时兜底存一次。
	AudioSettings.save_settings()
	WindowManager.close_current(owner)
