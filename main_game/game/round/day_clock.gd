extends Node

## 上班倒计时。走的是真实秒数，但显示成 9:00 → 18:00 的挂钟时间。
##
## 只在 RoundState.is_interactive()（也就是 GAME 段）走，剧情和结算时自动停。
## 笔记本开着也照走——玩家在里面翻邮件的时间是要付出代价的，这是玩法压力的一部分。

## 一天走完要多少真实秒。
@export var day_seconds: float = 180.0

## 挂钟的上班 / 下班时刻。
@export var start_hour: int = 9
@export var end_hour: int = 18

## 显示每多少分钟跳一格，避免每帧刷新 UI。
@export var display_step_minutes: int = 5

var save_id := "day_clock"

## 今天已经过去了多少真实秒。存档存这个。
var elapsed: float = 0.0

var _running := false
var _last_text := ""


func _ready() -> void:
	add_to_group(SaveState.GROUP)
	set_process(false)
	SignalBus.game_restored.connect(_on_game_restored)


## 开始新的一天，从头走。
func start() -> void:
	elapsed = 0.0
	_last_text = ""
	_running = true
	set_process(true)
	_emit_now()


func stop() -> void:
	_running = false
	set_process(false)


## 读档之后按恢复出来的 elapsed 接着走。
func resume() -> void:
	_last_text = ""
	_running = true
	set_process(true)
	_emit_now()


func _on_game_restored() -> void:
	if RoundState.is_interactive():
		resume()


func _process(delta: float) -> void:
	if not _running or not RoundState.is_interactive():
		return
	elapsed = minf(elapsed + delta, day_seconds)
	_emit_now()
	if elapsed >= day_seconds:
		stop()
		SignalBus.day_time_up.emit()


func ratio() -> float:
	if day_seconds <= 0.0:
		return 1.0
	return clampf(elapsed / day_seconds, 0.0, 1.0)


## 把进度映射成挂钟文本，按 display_step_minutes 取整。
func clock_text() -> String:
	var total_minutes := (end_hour - start_hour) * 60
	var minutes := int(ratio() * float(total_minutes))
	minutes -= minutes % maxi(display_step_minutes, 1)
	return "%d:%02d" % [start_hour + minutes / 60, minutes % 60]


func _emit_now() -> void:
	var t := clock_text()
	if t == _last_text:
		return
	_last_text = t
	SignalBus.day_time_changed.emit(t, ratio())


func save_data() -> Dictionary:
	return {"elapsed": elapsed}


func load_data(d: Dictionary) -> void:
	elapsed = d.get("elapsed", 0.0)
