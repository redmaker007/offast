extends Node

## 音量设置的自测。跑法见 tests/run_tests.ps1。
##
## 覆盖：总线布局、各音源挂对总线、音量换算与静音、存盘往返、设置面板的滑块联动。
##
## 全程不碰玩家的 user://settings.cfg：开跑前挪走，跑完挪回来。

const MENU_SCENE := "res://main_game/menu/menu_scene.tscn"
const CONFIG_PATH := "user://settings.cfg"
const BACKUP_PATH := "user://settings.cfg.audiotest_backup"

var _passed := 0
var _failed := 0
var _fail_lines: Array[String] = []
var _section := ""


func _ready() -> void:
	_stash_config()

	_test_bus_layout()
	_test_bgm_routed_to_music()
	await _test_ui_sounds_routed_to_sfx()
	_test_volume_applies_to_bus()
	_test_mute_at_zero()
	_test_unknown_bus_is_survivable()
	_test_persistence()
	await _test_settings_panel()
	_test_cue_uid_path()

	AudioSettings.reset()
	_restore_config()
	_report()


# ── 总线 ────────────────────────────────────────────────

func _test_bus_layout() -> void:
	_section = "总线布局"
	for name in ["Master", "Music", "SFX"]:
		_is_true("有 %s 总线" % name, AudioServer.get_bus_index(name) >= 0)
	var music := AudioServer.get_bus_index("Music")
	var sfx := AudioServer.get_bus_index("SFX")
	if music >= 0:
		_eq("Music 送到 Master", AudioServer.get_bus_send(music), &"Master")
	if sfx >= 0:
		_eq("SFX 送到 Master", AudioServer.get_bus_send(sfx), &"Master")


func _test_bgm_routed_to_music() -> void:
	_section = "BGM 挂 Music"
	var bgm := get_node_or_null("/root/Bgm")
	_is_true("Bgm autoload 在", bgm != null)
	if bgm == null:
		return
	_eq("播放器配置的总线", bgm.bus, AudioSettings.MUSIC)
	for i in range(bgm._players.size()):
		_eq("player %d 的总线" % i, bgm._players[i].bus, AudioSettings.MUSIC)


## hover_scale 和 popup_window 自己 new 出来的 player 要落在 SFX 上。
func _test_ui_sounds_routed_to_sfx() -> void:
	_section = "UI 音效挂 SFX"
	var menu := (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame

	var found := 0
	var wrong := 0
	for p in _all_audio_players(menu):
		found += 1
		if p.bus != AudioSettings.SFX:
			wrong += 1
	_is_true("菜单里找到了 UI 音效 player", found > 0, "找到 %d 个" % found)
	_eq("没挂在 SFX 上的个数", wrong, 0)

	menu.queue_free()
	await get_tree().process_frame


# ── 音量 ────────────────────────────────────────────────

func _test_volume_applies_to_bus() -> void:
	_section = "音量落到总线"
	var idx := AudioServer.get_bus_index("Music")
	AudioSettings.set_volume(AudioSettings.MUSIC, 0.5, false)
	_eq("内存里的值", AudioSettings.get_volume(AudioSettings.MUSIC), 0.5)
	_is_true("总线 dB 对得上",
		is_equal_approx(AudioServer.get_bus_volume_db(idx), linear_to_db(0.5)),
		"总线是 %f，期望 %f" % [AudioServer.get_bus_volume_db(idx), linear_to_db(0.5)])
	_is_false("被静音了", AudioServer.is_bus_mute(idx))

	# 越界的值要夹回 0..1。
	AudioSettings.set_volume(AudioSettings.SFX, 3.7, false)
	_eq("夹到上限", AudioSettings.get_volume(AudioSettings.SFX), 1.0)
	AudioSettings.set_volume(AudioSettings.SFX, -2.0, false)
	_eq("夹到下限", AudioSettings.get_volume(AudioSettings.SFX), 0.0)


func _test_mute_at_zero() -> void:
	_section = "拉到 0 = 静音"
	var idx := AudioServer.get_bus_index("Music")
	AudioSettings.set_volume(AudioSettings.MUSIC, 0.0, false)
	_is_true("总线被静音", AudioServer.is_bus_mute(idx))
	_is_true("dB 没变成 -inf", is_finite(AudioServer.get_bus_volume_db(idx)),
		"dB=%f" % AudioServer.get_bus_volume_db(idx))

	AudioSettings.set_volume(AudioSettings.MUSIC, 0.7, false)
	_is_false("拉回来解除静音", AudioServer.is_bus_mute(idx))


func _test_unknown_bus_is_survivable() -> void:
	_section = "不认识的总线"
	AudioSettings.set_volume(&"NoSuchBus", 0.5, false)
	_eq("查不认识的总线返回 1.0", AudioSettings.get_volume(&"NoSuchBus"), 1.0)
	_eq("没污染 Music", AudioSettings.get_volume(AudioSettings.MUSIC), 0.7)


func _test_persistence() -> void:
	_section = "存盘往返"
	AudioSettings.set_volume(AudioSettings.MUSIC, 0.33, false)
	AudioSettings.set_volume(AudioSettings.SFX, 0.66, false)
	AudioSettings.save_settings()
	_is_true("配置文件写出来了", FileAccess.file_exists(CONFIG_PATH))

	# 内存里改脏，再从盘上读回来。
	AudioSettings.set_volume(AudioSettings.MUSIC, 1.0, false)
	AudioSettings.set_volume(AudioSettings.SFX, 1.0, false)
	AudioSettings.load_settings()
	_is_true("BGM 读回来了", is_equal_approx(AudioSettings.get_volume(AudioSettings.MUSIC), 0.33),
		"读到 %f" % AudioSettings.get_volume(AudioSettings.MUSIC))
	_is_true("SFX 读回来了", is_equal_approx(AudioSettings.get_volume(AudioSettings.SFX), 0.66),
		"读到 %f" % AudioSettings.get_volume(AudioSettings.SFX))
	_is_true("读回来之后总线也跟着变了",
		is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")),
			linear_to_db(0.33)))

	# settings.cfg 里别的段不能被音量覆盖掉。
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("display", "fullscreen", true)
	cfg.save(CONFIG_PATH)
	AudioSettings.save_settings()
	var after := ConfigFile.new()
	after.load(CONFIG_PATH)
	_is_true("别的段还在", after.has_section_key("display", "fullscreen"))


# ── 设置面板 ────────────────────────────────────────────

func _test_settings_panel() -> void:
	_section = "设置面板"
	AudioSettings.set_volume(AudioSettings.MUSIC, 0.25, false)
	AudioSettings.set_volume(AudioSettings.SFX, 0.75, false)

	var menu := (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame

	var bgm_slider: Slider = menu.get_node("settings_panel/VBoxContainer/volume_rows/bgm_row/bgm_slider")
	var bgm_value: Label = menu.get_node("settings_panel/VBoxContainer/volume_rows/bgm_row/bgm_value")
	var sfx_slider: Slider = menu.get_node("settings_panel/VBoxContainer/volume_rows/sfx_row/sfx_slider")
	var sfx_value: Label = menu.get_node("settings_panel/VBoxContainer/volume_rows/sfx_row/sfx_value")

	_is_true("BGM 滑块摆到了当前值", is_equal_approx(bgm_slider.value, 0.25),
		"滑块是 %f" % bgm_slider.value)
	_is_true("SFX 滑块摆到了当前值", is_equal_approx(sfx_slider.value, 0.75),
		"滑块是 %f" % sfx_slider.value)
	_eq("BGM 百分比", bgm_value.text, "25%")
	_eq("SFX 百分比", sfx_value.text, "75%")

	# 拖滑块 → 设置和总线都要跟着走。
	bgm_slider.value = 0.4
	await get_tree().process_frame
	_is_true("拖动写进了设置", is_equal_approx(AudioSettings.get_volume(AudioSettings.MUSIC), 0.4),
		"设置里是 %f" % AudioSettings.get_volume(AudioSettings.MUSIC))
	_eq("百分比跟着变", bgm_value.text, "40%")
	_is_true("总线跟着变",
		is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")),
			linear_to_db(0.4)))

	# 反过来：外部改设置，滑块要回写。
	AudioSettings.set_volume(AudioSettings.SFX, 0.1, false)
	await get_tree().process_frame
	_is_true("外部改动回写到滑块", is_equal_approx(sfx_slider.value, 0.1),
		"滑块是 %f" % sfx_slider.value)
	_eq("百分比也回写了", sfx_value.text, "10%")

	# 关闭按钮走 WindowManager，不能直接 close()。
	var panel := menu.get_node("settings_panel")
	panel._on_close_pressed()
	await get_tree().process_frame
	_is_true("关闭时存了盘", FileAccess.file_exists(CONFIG_PATH))

	menu.queue_free()
	await get_tree().process_frame


# ── 顺手：cue 的 uid 路径 ───────────────────────────────

## Inspector 的文件选择器填的是 uid://，得换算成 res:// 才匹配得上转场路径。
func _test_cue_uid_path() -> void:
	_section = "cue 的 uid 路径"
	var uid := ResourceUID.id_to_text(ResourceUID.text_to_id(_uid_of(MENU_SCENE)))
	var c := bgm_cue.new()
	c.scene_path = uid
	_eq("uid 换算成 res 路径", c.target_path(), MENU_SCENE)

	c.scene_path = "uid://zzzzzzzzzzzzz"
	_eq("认不出的 uid 原样返回", c.target_path(), "uid://zzzzzzzzzzzzz")


func _uid_of(path: String) -> String:
	return ResourceUID.id_to_text(ResourceLoader.get_resource_uid(path))


# ── 杂 ──────────────────────────────────────────────────

func _all_audio_players(root: Node) -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AudioStreamPlayer:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _stash_config() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		DirAccess.rename_absolute(CONFIG_PATH, BACKUP_PATH)


func _restore_config() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		DirAccess.remove_absolute(CONFIG_PATH)
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.rename_absolute(BACKUP_PATH, CONFIG_PATH)


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
	print("\n=========== audio_settings_test ===========")
	if _failed == 0:
		print("全部通过：%d 项" % _passed)
	else:
		print("通过 %d 项，失败 %d 项：" % [_passed, _failed])
		for line in _fail_lines:
			print(line)
	print("===========================================\n")
	get_tree().quit(1 if _failed > 0 else 0)
