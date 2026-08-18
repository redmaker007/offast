extends Node

## BGM 播放器的自测。跑法见 tests/run_tests.ps1。
##
## 覆盖：cue 两种填法的匹配、倍率换算的三条路、换曲、
## 「不配曲子只改速度」这条需求核心、交叉淡入淡出、跟着 SceneTransition 走。

const MENU_SCENE := "res://main_game/menu/menu_scene.tscn"
const GAME_SCENE := "res://main_game/game/main_scene.tscn"
const PLAYER_SCENE := "res://addons/bgm/bgm_player.tscn"
const TRACK_A := "res://sound/bgm/offast_bgm.mp3"
const TRACK_B := "res://sound/guitar.mp3"

var _passed := 0
var _failed := 0
var _fail_lines: Array[String] = []
var _section := ""


func _ready() -> void:
	_test_autoload_wiring()
	_test_exports_survived_on_disk()
	_test_cue_target_path()
	_test_cue_speed()
	await _test_hard_switch()
	await _test_same_track_is_not_restarted()
	await _test_crossfade()
	await _test_speed_only_cue()
	await _test_unknown_scene_changes_nothing()
	await _test_follows_scene_transition()
	_report()


# ── 装配 ────────────────────────────────────────────────

func _test_autoload_wiring() -> void:
	_section = "装配"
	var bgm := _bgm()
	_is_true("autoload 存在", bgm != null)
	if bgm == null:
		return
	_eq("player 个数", bgm._players.size(), 2)
	_eq("player 0 的总线", bgm._players[0].bus, bgm.bus)
	_eq("player 1 的总线", bgm._players[1].bus, bgm.bus)
	_is_false("一开始就在放", bgm.is_playing())
	_is_true("接上了转场信号",
		SceneTransition.transition_finished.is_connected(bgm._on_transition_finished))


## Godot 给已有节点换脚本 / 新增 @export 时会把导出属性存成 null，
## 而且编辑器内存里读到的还是对的，只有从磁盘重新加载才暴露。
func _test_exports_survived_on_disk() -> void:
	_section = "磁盘上的 @export"
	var packed := ResourceLoader.load(PLAYER_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	_is_true("场景能加载", packed != null)
	if packed == null:
		return
	var inst := (packed as PackedScene).instantiate()   # 不加进树，_ready 不会跑
	for prop in ["cues", "auto_follow_scene", "volume_db", "bus",
			"fade_by_default", "fade_duration", "speed_ramp_duration"]:
		_is_true("%s 不是 null" % prop, inst.get(prop) != null, "读到的是 null")
	_is_true("cues 是数组", inst.get("cues") is Array)
	_is_true("fade_duration 是正数", float(inst.get("fade_duration")) > 0.0)
	inst.free()


# ── 纯数据：bgm_cue ─────────────────────────────────────

func _test_cue_target_path() -> void:
	_section = "cue 指向的场景"
	var by_path := bgm_cue.new()
	by_path.scene_path = MENU_SCENE
	_eq("只填路径", by_path.target_path(), MENU_SCENE)

	var by_scene := bgm_cue.new()
	by_scene.scene = load(MENU_SCENE)
	_eq("只拖场景", by_scene.target_path(), MENU_SCENE)

	# 两个都填时拖进来的那个说了算。
	var both := bgm_cue.new()
	both.scene = load(MENU_SCENE)
	both.scene_path = GAME_SCENE
	_eq("两个都填", both.target_path(), MENU_SCENE)

	_eq("两个都空", bgm_cue.new().target_path(), "")


func _test_cue_speed() -> void:
	_section = "倍率换算"
	var c := bgm_cue.new()
	_eq("bpm 留空 = 不动速度", c.speed(), 0.0)

	c.bpm = 140.0
	c.source_bpm = 120.0
	_is_true("填了原速就按比例算", is_equal_approx(c.speed(), 140.0 / 120.0), "得到 %f" % c.speed())

	c.source_bpm = 0.0
	c.bpm = 1.25
	_is_true("没有原速就当倍率用", is_equal_approx(c.speed(), 1.25), "得到 %f" % c.speed())

	# 曲子自带的 Bpm 元数据也算原速，优先级低于手填的 source_bpm。
	var stream: AudioStream = load(TRACK_A)
	var had := float(stream.get("bpm"))
	stream.set("bpm", 100.0)
	c.stream = stream
	c.bpm = 150.0
	_is_true("读 stream 自带的 Bpm", is_equal_approx(c.speed(), 1.5), "得到 %f" % c.speed())
	c.source_bpm = 75.0
	_is_true("手填的原速优先", is_equal_approx(c.speed(), 2.0), "得到 %f" % c.speed())
	stream.set("bpm", had)


# ── 播放行为 ────────────────────────────────────────────

func _test_hard_switch() -> void:
	_section = "硬切换曲"
	var bgm := _bgm()
	var before := bgm._active

	bgm.play(load(TRACK_A), 1.0, 0.0, true, false)
	await _frames(2)
	_eq("换到了另一个 player", bgm._active, 1 - before)
	_eq("正在放的曲子", bgm.current_stream().resource_path, TRACK_A)
	_is_true("在放", bgm.is_playing())
	_is_true("音量到位", is_equal_approx(bgm._players[bgm._active].volume_db, bgm.volume_db),
		"volume_db=%f" % bgm._players[bgm._active].volume_db)
	_is_true("循环被打开", bool(load(TRACK_A).get("loop")))

	var previous := bgm._active
	bgm.play(load(TRACK_B), 1.5, 0.0, true, false)
	await _frames(2)
	_eq("又换回另一个 player", bgm._active, 1 - previous)
	_eq("正在放的曲子", bgm.current_stream().resource_path, TRACK_B)
	_is_true("速度到位", is_equal_approx(bgm._players[bgm._active].pitch_scale, 1.5),
		"pitch_scale=%f" % bgm._players[bgm._active].pitch_scale)
	_eq("播放器记的速度", bgm.current_speed(), 1.5)
	_is_false("旧 player 还在放", bgm._players[previous].playing)


func _test_same_track_is_not_restarted() -> void:
	_section = "重复请求同一首"
	var bgm := _bgm()
	bgm.play(load(TRACK_A), 1.0, 0.0, true, false)
	await _frames(2)
	var player_index := bgm._active
	var pos := bgm._players[player_index].get_playback_position()

	bgm.play(load(TRACK_A), 1.2, 0.0, true, false)
	await _frames(2)
	_eq("没换 player", bgm._active, player_index)
	_is_true("没从头开始", bgm._players[player_index].get_playback_position() >= pos,
		"原来 %f，现在 %f" % [pos, bgm._players[player_index].get_playback_position()])
	_is_true("速度还是调到了", is_equal_approx(bgm.current_speed(), 1.2),
		"speed=%f" % bgm.current_speed())


func _test_crossfade() -> void:
	_section = "交叉淡入淡出"
	var bgm := _bgm()
	bgm.play(load(TRACK_A), 1.0, 0.0, true, false)
	await _frames(2)
	var old_index := bgm._active

	bgm.play(load(TRACK_B), 1.0, 0.0, true, true, 0.4)
	await _frames(2)
	_eq("换了 player", bgm._active, 1 - old_index)
	_is_true("渐变途中两个都在放", bgm._players[0].playing and bgm._players[1].playing)
	_is_true("新曲子从静音起步", bgm._players[bgm._active].volume_db < bgm.volume_db,
		"volume_db=%f" % bgm._players[bgm._active].volume_db)

	await get_tree().create_timer(0.7).timeout
	_is_false("旧 player 已经停了", bgm._players[old_index].playing)
	_is_true("新曲子淡到了目标音量",
		is_equal_approx(bgm._players[bgm._active].volume_db, bgm.volume_db),
		"volume_db=%f" % bgm._players[bgm._active].volume_db)


## 需求核心：cue 没配曲子，就不换曲，但速度照吃。
func _test_speed_only_cue() -> void:
	_section = "只改速度不换曲"
	var bgm := _bgm()
	bgm.play(load(TRACK_A), 1.0, 0.0, true, false)
	await _frames(2)
	var player_index := bgm._active

	var cue := bgm_cue.new()
	cue.scene_path = GAME_SCENE
	cue.stream = null          # 关键：不配曲子
	cue.bpm = 0.8              # 没有原速，当倍率用
	bgm.apply_cue(cue)
	await _frames(2)

	_eq("没换 player", bgm._active, player_index)
	_eq("曲子没变", bgm.current_stream().resource_path, TRACK_A)
	_is_true("还在放", bgm.is_playing())
	_is_true("速度变了", is_equal_approx(bgm.current_speed(), 0.8), "speed=%f" % bgm.current_speed())

	# 爬坡用的必须是 speed_ramp_duration，不是（通常长得多的）fade_duration。
	await get_tree().create_timer(bgm.speed_ramp_duration + 0.3).timeout
	_is_true("pitch_scale 爬到位",
		is_equal_approx(bgm._players[player_index].pitch_scale, 0.8),
		"pitch_scale=%f" % bgm._players[player_index].pitch_scale)


func _test_unknown_scene_changes_nothing() -> void:
	_section = "表里没有的场景"
	var bgm := _bgm()
	bgm.play(load(TRACK_A), 1.1, 0.0, true, false)
	await _frames(2)
	var player_index := bgm._active
	var speed := bgm.current_speed()

	bgm.apply_scene("res://nowhere/not_a_scene.tscn")
	await _frames(2)
	_eq("没换 player", bgm._active, player_index)
	_eq("曲子没变", bgm.current_stream().resource_path, TRACK_A)
	_eq("速度没变", bgm.current_speed(), speed)
	_is_true("还在放", bgm.is_playing())


# ── 端到端 ──────────────────────────────────────────────

## 真的走一遍 SceneTransition，看曲子跟不跟着换。
func _test_follows_scene_transition() -> void:
	_section = "跟着场景切换走"
	var bgm := _bgm()

	var menu_cue := bgm_cue.new()
	menu_cue.scene_path = MENU_SCENE
	menu_cue.stream = load(TRACK_A)
	menu_cue.fade = bgm_cue.Fade.OFF

	var game_cue := bgm_cue.new()
	game_cue.scene = load(GAME_SCENE)     # 这一行故意用拖场景的填法
	game_cue.stream = load(TRACK_B)
	game_cue.bpm = 1.4
	game_cue.fade = bgm_cue.Fade.OFF

	bgm.cues = [menu_cue, game_cue]
	bgm.stop(false)
	SceneTransition.clear_retained()

	# bpm 留空 = 不动速度，所以换新曲子会**沿用当前倍率**（需求里的 default 为不变）。
	# 想让某个场景回到原速就把它的 bpm 填成 1.0。
	bgm.set_speed(1.3, 0.0)

	SceneTransition.goto(MENU_SCENE, SceneTransition.Slide.NONE)
	await _await_transition(MENU_SCENE)
	_eq("菜单的曲子", bgm.current_stream().resource_path, TRACK_A)
	_is_true("在放", bgm.is_playing())
	_is_true("没配速度就沿用当前倍率", is_equal_approx(bgm.current_speed(), 1.3),
		"speed=%f" % bgm.current_speed())

	SceneTransition.goto(GAME_SCENE, SceneTransition.Slide.NONE)
	await _await_transition(GAME_SCENE)
	_eq("游戏的曲子", bgm.current_stream().resource_path, TRACK_B)
	_is_true("速度按 cue 调了", is_equal_approx(bgm.current_speed(), 1.4),
		"speed=%f" % bgm.current_speed())
	_eq("记住了是哪一行", bgm.current_cue(), game_cue)

	# 拖场景的填法也要能匹配上。
	_eq("拖场景的 cue 匹配", bgm.cue_for(GAME_SCENE), game_cue)

	# 想回原速就把 bpm 填成 1.0（没有 source_bpm 时它就是倍率）。
	menu_cue.bpm = 1.0
	SceneTransition.goto(MENU_SCENE, SceneTransition.Slide.NONE)
	await _await_transition(MENU_SCENE)
	await get_tree().create_timer(bgm.speed_ramp_duration + 0.3).timeout
	_is_true("bpm 填 1.0 能拉回原速", is_equal_approx(bgm.current_speed(), 1.0),
		"speed=%f" % bgm.current_speed())

	bgm.stop(false)
	SceneTransition.clear_retained()


func _await_transition(expected_path: String) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if SceneTransition.current_path == expected_path and not SceneTransition._busy:
			break
		await get_tree().process_frame
	_record("转场落到 %s" % expected_path.get_file(),
		SceneTransition.current_path == expected_path and not SceneTransition._busy,
		"current_path=%s, busy=%s" % [SceneTransition.current_path, SceneTransition._busy])


# ── 杂 ──────────────────────────────────────────────────

func _bgm() -> bgm_player:
	return get_node_or_null("/root/Bgm") as bgm_player


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _eq(label: String, actual: Variant, expected: Variant) -> void:
	_record(label, actual == expected, "期望 %s，实际 %s" % [str(expected), str(actual)])


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
	print("\n================ bgm_test =================")
	if _failed == 0:
		print("全部通过：%d 项" % _passed)
	else:
		print("通过 %d 项，失败 %d 项：" % [_passed, _failed])
		for line in _fail_lines:
			print(line)
	print("===========================================\n")
	get_tree().quit(1 if _failed > 0 else 0)
