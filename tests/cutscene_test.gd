extends Node

## 动画（cutscene）的自测。跑法见 tests/run_tests.ps1。
##
## 覆盖：播放期间锁交互、时钟停、播满放开并发 finished、
## 设置面板开着暂停计时、回主菜单（挂起）退回开始前并发 cancelled、
## 场景销毁时不把锁留下。

const GAME_SCENE := "res://main_game/game/main_scene.tscn"

var _passed := 0
var _failed := 0
var _fail_lines: Array[String] = []
var _section := ""

var _game: Node
var _layer: CanvasLayer
var _cut: cutscene
var _events: Array[String] = []


func _ready() -> void:
	_game = load(GAME_SCENE).instantiate()
	_layer = CanvasLayer.new()
	_layer.add_child(_game)
	get_tree().root.add_child.call_deferred(_layer)
	await get_tree().process_frame
	await get_tree().process_frame

	_cut = cutscene.new()
	_cut.duration = 0.3
	_game.add_child(_cut)
	_cut.started.connect(func(): _events.append("started"))
	_cut.finished.connect(func(): _events.append("finished"))
	_cut.cancelled.connect(func(): _events.append("cancelled"))
	RoundState.current_round_state = RoundState.Round_State.GAME

	await _test_play_locks_then_releases()
	await _test_settings_pauses()
	await _test_suspend_reverts()
	_test_freed_releases_lock()
	_report()


func _test_play_locks_then_releases() -> void:
	_section = "播放"
	_events.clear()
	_is_true("播之前能交互", RoundState.is_interactive())
	var clock: Node = _game.get_node("%day_clock")
	clock.start()
	_cut.play()
	_is_true("在播", _cut.is_playing())
	_is_false("播放期间不能交互", RoundState.is_interactive())
	_eq("发了 started", _events, ["started"])
	var clock_before: float = clock.elapsed
	await get_tree().create_timer(0.15).timeout
	_eq("播放期间时钟停着", clock.elapsed, clock_before)
	_is_true("还没播完", _cut.is_playing())
	await get_tree().create_timer(0.3).timeout
	_is_false("播完了", _cut.is_playing())
	_is_true("播完放开交互", RoundState.is_interactive())
	_eq("发了 finished", _events, ["started", "finished"])
	clock.stop()


func _test_settings_pauses() -> void:
	_section = "设置面板暂停"
	_events.clear()
	_cut.play()
	WindowManager.open_window(_game.get_node("%settings_panel"))
	# 开局可能有提示气泡开着，WindowManager 要等它的关闭动画播完才换成设置面板。
	await get_tree().create_timer(0.3).timeout
	_is_true("设置开着算暂停", _cut.is_paused())
	await get_tree().create_timer(0.5).timeout
	_is_true("暂停期间超过 duration 也不结束", _cut.is_playing())
	_is_false("暂停期间仍然锁着", RoundState.is_interactive())
	WindowManager.close_current(_game)
	await get_tree().create_timer(0.25).timeout
	_is_false("关掉设置后不再暂停", _cut.is_paused())
	await get_tree().create_timer(0.4).timeout
	_is_false("关掉设置后接着播完", _cut.is_playing())
	_eq("发了 finished", _events, ["started", "finished"])


func _test_suspend_reverts() -> void:
	_section = "回主菜单"
	_events.clear()
	_cut.play()
	await get_tree().create_timer(0.1).timeout
	# SceneTransition 挂起场景时调的就是这个。
	_game._scene_suspended()
	_is_false("被打断不在播", _cut.is_playing())
	_eq("计时清零", _cut.get_elapsed(), 0.0)
	_is_true("交互放开", RoundState.is_interactive())
	_eq("发了 cancelled 而不是 finished", _events, ["started", "cancelled"])


func _test_freed_releases_lock() -> void:
	_section = "场景销毁"
	_cut.play()
	_is_false("播放中锁着", RoundState.is_interactive())
	get_tree().root.remove_child(_layer)
	_layer.free()
	_is_true("销毁后锁跟着解开", RoundState.is_interactive())


func _eq(label: String, actual: Variant, expected: Variant) -> void:
	_record(label, actual == expected, "实际 %s，期望 %s" % [actual, expected])


func _is_true(label: String, cond: bool, detail := "") -> void:
	_record(label, cond, "期望为真" if detail.is_empty() else detail)


func _is_false(label: String, cond: bool, detail := "") -> void:
	_record(label, not cond, "期望为假" if detail.is_empty() else detail)


func _record(label: String, ok: bool, detail: String) -> void:
	if ok:
		_passed += 1
		return
	_failed += 1
	_fail_lines.append("  ✗ [%s] %s —— %s" % [_section, label, detail])


func _report() -> void:
	print("\n=============== cutscene_test =============")
	if _failed == 0:
		print("全部通过：%d 项" % _passed)
	else:
		print("通过 %d 项，失败 %d 项：" % [_passed, _failed])
		for line in _fail_lines:
			print(line)
	print("===========================================\n")
	get_tree().quit(1 if _failed > 0 else 0)
