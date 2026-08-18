extends Node

## 音量设置（autoload `AudioSettings`）。
##
## 存在 `user://settings.cfg`，**和游戏存档分开**——开新局、删档、被开除都不该
## 把玩家调好的音量冲掉，所以不走 SaveState 那套。
##
## 音量本身落在音频总线上，不在各个 player 上：BGM 走 Music，UI 音效走 SFX，
## 加新音源只要挂对总线就自动受设置控制，不用再去改一遍代码。
## 总线定义在 res://default_bus_layout.tres。
##
## 用法：
##     AudioSettings.set_volume(AudioSettings.MUSIC, 0.6)
##     AudioSettings.get_volume(AudioSettings.SFX)

const MUSIC := &"Music"
const SFX := &"SFX"

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "audio"

## 滑到底就直接静音。linear_to_db(0) 是 -inf，交给总线的 mute 更干净。
const MUTE_THRESHOLD := 0.0005

## 总线名 -> 默认音量（0..1 线性）。
const DEFAULTS := {
	MUSIC: 0.8,
	SFX: 0.8,
}

## 某条总线的音量变了。UI 靠这个回写滑块（比如读档 / 重置之后）。
signal volume_changed(bus: StringName, linear: float)

var _volumes: Dictionary = {}


func _ready() -> void:
	# 音量落在总线上，和 Bgm 这类音源谁先 _ready 无关——总线在引擎起来时就有了。
	for bus in DEFAULTS:
		_volumes[bus] = float(DEFAULTS[bus])
	load_settings()


## 0..1 的线性音量。总线名不认识就返回 1.0（当作没有限制）。
func get_volume(bus: StringName) -> float:
	return float(_volumes.get(bus, 1.0))


## 设音量并立刻生效。save 传 false 可以做「拖动预览、松手才存」。
func set_volume(bus: StringName, linear: float, save := true) -> void:
	if not _volumes.has(bus):
		push_warning("AudioSettings 不认识的总线：%s" % bus)
		return
	var v := clampf(linear, 0.0, 1.0)
	if is_equal_approx(v, float(_volumes[bus])) and _is_applied(bus, v):
		return
	_volumes[bus] = v
	_apply(bus)
	volume_changed.emit(bus, v)
	if save:
		save_settings()


## 全部恢复默认。
func reset() -> void:
	for bus in DEFAULTS:
		set_volume(bus, float(DEFAULTS[bus]), false)
	save_settings()


# ── 落盘 ────────────────────────────────────────────────

func save_settings() -> void:
	var cfg := ConfigFile.new()
	# 先读一遍再写：settings.cfg 以后可能还放别的段（画面、语言），别覆盖掉。
	cfg.load(CONFIG_PATH)
	for bus in _volumes:
		cfg.set_value(SECTION, String(bus).to_lower(), _volumes[bus])
	var err := cfg.save(CONFIG_PATH)
	if err != OK:
		push_error("音量设置写入失败（%s）：%d" % [CONFIG_PATH, err])


func load_settings() -> void:
	var cfg := ConfigFile.new()
	# 没有文件是正常情况（第一次玩），用默认值，照样要 apply 一遍。
	if cfg.load(CONFIG_PATH) == OK:
		for bus in _volumes:
			var key := String(bus).to_lower()
			if cfg.has_section_key(SECTION, key):
				_volumes[bus] = clampf(float(cfg.get_value(SECTION, key)), 0.0, 1.0)
	for bus in _volumes:
		_apply(bus)
		volume_changed.emit(bus, float(_volumes[bus]))


# ── 总线 ────────────────────────────────────────────────

func _apply(bus: StringName) -> void:
	var idx := AudioServer.get_bus_index(String(bus))
	if idx < 0:
		# 总线布局没加载（比如有人删了 default_bus_layout.tres）。
		# 不硬崩，声音退回原样，只提醒一句。
		push_warning("音频总线不存在：%s，音量设置对它无效" % bus)
		return
	var v := float(_volumes[bus])
	AudioServer.set_bus_mute(idx, v <= MUTE_THRESHOLD)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, MUTE_THRESHOLD)))


func _is_applied(bus: StringName, v: float) -> bool:
	var idx := AudioServer.get_bus_index(String(bus))
	if idx < 0:
		return true
	return AudioServer.is_bus_mute(idx) == (v <= MUTE_THRESHOLD)
