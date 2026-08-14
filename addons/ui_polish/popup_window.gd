extends PanelContainer
class_name popup_window

## 弹窗基类：负责 pop-in / pop-out 的小动画，以及缩放要用的 pivot。
##
## 子类不要直接改 visible，改用 open() / close()，两个都能 await：
##     await old_window.close()
##     await new_window.open()
##
## 窗口之间谁先谁后交给 WindowManager 排，别在各自脚本里互相 close，
## 不然加了动画之后两个窗口会在同一帧重叠。

## 弹出动画时长（秒）。
@export var open_duration: float = 0.22

## 关闭动画时长（秒）。比弹出快一点手感更利落。
@export var close_duration: float = 0.13

## 弹出起手 / 关闭收尾的缩放倍数。比 1 小就是"从小弹到大"。
@export_range(0.1, 1.0, 0.01) var pop_scale: float = 0.85

## 弹出时是否带回弹过冲（TRANS_BACK）。关掉就是干净的 EASE_OUT。
@export var bounce: bool = true

## 弹出音效，在 Inspector 里拖入音频文件（留空则不播放）。
@export var open_sound: AudioStream

## 关闭音效（留空则不播放）。
@export var close_sound: AudioStream

## 开关音效的音量。
@export_range(0.0, 1.0, 0.01) var sound_volume: float = 1.0

## 动画播完之后才发，用来接"窗口就位了再放内容动画"这类后续。
signal opened
## 关闭动画播完、visible 已经关掉之后发。
signal closed

## 当前是不是打开状态。动画一开始就会翻，所以重复调用 open() 不会重放动画。
var is_open := false

## 场景里设好的原始 scale，所有动画以它为基准，不覆盖美术调好的大小。
var _base_scale := Vector2.ONE
var _tween: Tween
var _audio: AudioStreamPlayer
## 每次动画自增，await 回来发现对不上就说明这次动画被后来的请求顶掉了。
var _anim_token := 0


func _ready() -> void:
	_base_scale = scale
	is_open = visible

	# size 变了 pivot 就得跟着变，不然缩放原点会跑偏（和 hover_scale 一个套路）。
	resized.connect(_apply_pivot)
	_apply_pivot()

	_audio = AudioStreamPlayer.new()
	add_child(_audio)

	if is_open:
		# 场景里就摆成显示状态的窗口，要让管理器知道，否则它以为一个窗口都没开。
		WindowManager.adopt(self)


## 弹出窗口。可以 await，动画播完才返回。
func open() -> void:
	if is_open:
		return
	is_open = true
	_kill_tween()
	_anim_token += 1
	var token := _anim_token

	# 起始状态先摆好再 show，这样显示出来的第一帧就已经是缩小 + 透明的，不会闪一下全尺寸。
	# pivot 也要在改 scale 之前设好——先缩放再挪 pivot 的话画面会跳。
	_apply_pivot()
	modulate.a = 0.0
	scale = _base_scale * pop_scale
	visible = true
	_play(open_sound)

	_tween = create_tween().set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_BACK if bounce else Tween.TRANS_CUBIC)
	_tween.tween_property(self, "scale", _base_scale, open_duration)
	# 透明度比缩放先收，免得回弹那段还是半透明的。
	_tween.parallel().tween_property(self, "modulate:a", 1.0, open_duration * 0.6)

	# 用计时器而不是 tween.finished：tween 被 kill 掉时不会发 finished，
	# await 的那一头会永远卡住。
	await get_tree().create_timer(open_duration).timeout
	if token != _anim_token:
		return
	opened.emit()


## 关闭窗口。可以 await，动画播完、visible 关掉之后才返回。
func close() -> void:
	if not is_open:
		return
	is_open = false
	_kill_tween()
	_anim_token += 1
	var token := _anim_token
	_play(close_sound)

	_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "scale", _base_scale * pop_scale, close_duration)
	_tween.parallel().tween_property(self, "modulate:a", 0.0, close_duration)

	await get_tree().create_timer(close_duration).timeout
	if token != _anim_token:
		return
	visible = false
	# 复位，让下一次 open() 从干净的状态起手。
	scale = _base_scale
	modulate.a = 1.0
	closed.emit()


func _apply_pivot() -> void:
	# 容器还没排过版时 size 是 0，先拿 custom_minimum_size 顶上，
	# 免得第一次弹出的时候 pivot 落在左上角、窗口从角上炸出来。
	var s := size
	if s == Vector2.ZERO:
		s = custom_minimum_size
	pivot_offset = s / 2.0


func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	_audio.stream = stream
	_audio.volume_db = linear_to_db(maxf(sound_volume, 0.0001))
	_audio.play()


func _kill_tween() -> void:
	if _tween:
		_tween.kill()
		_tween = null
