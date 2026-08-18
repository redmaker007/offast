extends Node
class_name bgm_player

## 全局 BGM 播放器（autoload `Bgm`）。
##
## 曲子跟着场景走：每次 SceneTransition 转场落地，就拿新场景的路径去 cues 里查表。
##   查不到这个场景        —— 什么都不做，当前这首接着放
##   查到了但 stream 留空  —— 也不换曲，但速度按这一行的设置改
##   查到了带 stream       —— 换曲（要不要渐变看配置）
##
## 换曲用两个 AudioStreamPlayer 交叉淡入淡出：一个淡出的同时另一个淡入，
## 中间不断声。单个 player 做不到——换 stream 会立刻掐掉正在响的声音。
##
## 配置在 addons/bgm/bgm_player.tscn 上，用 Inspector 编辑。
## autoload 必须挂**场景**而不是纯脚本，不然 @export 在编辑器里根本没地方填。
##
## 也可以绕过表直接调：
##     Bgm.play(load("res://sound/bgm/xxx.mp3"))
##     Bgm.set_speed(1.25)          # 1.25 倍速
##     Bgm.set_bpm(140.0, 120.0)    # 原速 120 的曲子放成 140
##     Bgm.stop()

## 淡出的目标音量。-80 以下听不见了，留点余量方便 tween 插值。
const SILENT_DB := -60.0


## 场景 → BGM 的对照表。在 Inspector 里点 + 新建 bgm_cue，一行配一个场景。
@export var cues: Array[bgm_cue] = []

## 关掉就不再自动跟场景换曲，只能手动调 play() / apply_cue()。
@export var auto_follow_scene: bool = true

## 全局音量。每一行 cue 自己的 volume_db 会叠加在这个上面。
@export_range(-60.0, 12.0, 0.1, "suffix:dB") var volume_db: float = 0.0

## 走哪条音频总线。默认 Music，音量归 AudioSettings 管（设置面板里的 BGM 滑块）。
@export var bus: StringName = &"Music"


@export_group("渐变")

## 没有单独指定的 cue 用这个。关掉就是硬切。
@export var fade_by_default: bool = true

## 换曲的交叉淡入淡出时长（秒）。
@export var fade_duration: float = 1.5

## 只改速度不换曲时，速度爬到位要多久（秒）。0 = 立刻跳过去。
@export var speed_ramp_duration: float = 0.5


## 两个轮着用的 player，_active 指向正在响的那个。
var _players: Array[AudioStreamPlayer] = []
var _active := 0

## 淡入淡出和速度爬坡各用各的 tween，互相不打断。
var _fade_tween: Tween
var _speed_tween: Tween

var _current_speed := 1.0
var _current_cue: bgm_cue = null


func _ready() -> void:
	# 游戏暂停时音乐不该跟着停。
	process_mode = Node.PROCESS_MODE_ALWAYS

	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.name = "player_%d" % i
		p.bus = bus
		p.volume_db = SILENT_DB
		add_child(p)
		_players.append(p)

	if not auto_follow_scene:
		return
	# 不硬依赖 SceneTransition：拿不到就退化成纯手动播放器。
	var router := get_node_or_null("/root/SceneTransition")
	if router == null or not router.has_signal("transition_finished"):
		return
	router.transition_finished.connect(_on_transition_finished)
	# autoload 的 _ready 跑在任何场景之前，正常这里是空的；
	# 万一播放器是后加进树的，就把当前场景补应用一次。
	if not str(router.current_path).is_empty():
		apply_scene(str(router.current_path))


# ── 跟着场景走 ──────────────────────────────────────────

func _on_transition_finished(path: String) -> void:
	apply_scene(path)


## 按场景路径查表并应用。表里没有这个场景就什么都不做。
func apply_scene(path: String) -> void:
	var cue := cue_for(path)
	if cue == null:
		return
	apply_cue(cue)


## 表里管这个场景的那一行，没有就是 null。
func cue_for(path: String) -> bgm_cue:
	for cue in cues:
		if cue != null and cue.target_path() == path:
			return cue
	return null


## 应用一行配置。stream 留空就只改速度，不打断当前这首。
func apply_cue(cue: bgm_cue) -> void:
	if cue == null:
		return
	var speed := cue.speed()

	if cue.stream == null:
		# 需求核心：没配曲子的场景不换曲，但速度照吃。
		if speed > 0.0:
			set_speed(speed, _ramp_time_of(cue))
		return

	_current_cue = cue
	play(cue.stream, speed, cue.volume_db, cue.loop, _fades(cue), _fade_time_of(cue))


# ── 播放控制 ────────────────────────────────────────────

## 换曲。speed <= 0 表示沿用当前倍率；fade_time 为负表示用全局时长。
func play(stream: AudioStream, speed := 0.0, track_volume_db := 0.0,
		loop := true, use_fade := true, fade_time := -1.0) -> void:
	if stream == null:
		return
	_apply_loop(stream, loop)
	if speed <= 0.0:
		speed = _current_speed

	var target_db := volume_db + track_volume_db
	var current := _players[_active]

	# 已经在放同一首了：不重头开始，只把速度和音量调到位。
	if current.stream == stream and current.playing:
		set_speed(speed, -1.0 if use_fade else 0.0)
		current.volume_db = target_db
		return

	var next := _players[1 - _active]
	next.stream = stream
	next.pitch_scale = speed
	next.volume_db = SILENT_DB
	next.play()

	_active = 1 - _active
	_current_speed = speed

	var t := _resolve_fade_time(fade_time) if use_fade else 0.0
	_kill(_fade_tween)
	# 换曲期间旧的速度爬坡没意义了，一起停掉。
	_kill(_speed_tween)

	if t <= 0.0:
		current.stop()
		next.volume_db = target_db
		return

	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_method(_set_db.bind(next), SILENT_DB, target_db, t)
	_fade_tween.tween_method(_set_db.bind(current), current.volume_db, SILENT_DB, t)
	_fade_tween.chain().tween_callback(current.stop)


## 改播放速度。1.0 是原速。ramp 为负表示用全局的 speed_ramp_duration，0 是立刻。
##
## 引擎没有变速不变调，这里动的是 pitch_scale，音高会跟着一起变。
func set_speed(speed: float, ramp := -1.0) -> void:
	if speed <= 0.0:
		return
	_current_speed = speed

	var p := _players[_active]
	var t := speed_ramp_duration if ramp < 0.0 else ramp
	_kill(_speed_tween)
	if t <= 0.0 or not p.playing:
		p.pitch_scale = speed
		return
	_speed_tween = create_tween()
	_speed_tween.tween_property(p, "pitch_scale", speed, t)


## 按 BPM 改速度。source 是曲子的原速，<= 0 时把 bpm 直接当倍率用。
func set_bpm(bpm: float, source := 0.0, ramp := -1.0) -> void:
	if bpm <= 0.0:
		return
	set_speed(bpm / source if source > 0.0 else bpm, ramp)


## 停掉当前的曲子。
func stop(use_fade := true, fade_time := -1.0) -> void:
	var p := _players[_active]
	if not p.playing:
		return
	_current_cue = null
	var t := _resolve_fade_time(fade_time) if use_fade else 0.0
	_kill(_fade_tween)
	if t <= 0.0:
		p.stop()
		return
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_db.bind(p), p.volume_db, SILENT_DB, t)
	_fade_tween.tween_callback(p.stop)


# ── 状态查询 ────────────────────────────────────────────

func is_playing() -> bool:
	return _players[_active].playing


func current_stream() -> AudioStream:
	return _players[_active].stream


func current_speed() -> float:
	return _current_speed


## 最后一次换曲用的是哪一行配置，手动 play() 过就是 null。
func current_cue() -> bgm_cue:
	return _current_cue


# ── 内部 ────────────────────────────────────────────────

func _fades(cue: bgm_cue) -> bool:
	match cue.fade:
		bgm_cue.Fade.ON:
			return true
		bgm_cue.Fade.OFF:
			return false
	return fade_by_default


func _fade_time_of(cue: bgm_cue) -> float:
	return fade_duration if cue.fade_duration < 0.0 else cue.fade_duration


## 只改速度不换曲时用的爬坡时长。默认走 speed_ramp_duration 而不是 fade_duration——
## 后者是给交叉淡入淡出用的，通常长得多，拿来爬速度会慢得像在拖。
## 这一行显式填了 fade_duration 才用它。
func _ramp_time_of(cue: bgm_cue) -> float:
	if not _fades(cue):
		return 0.0
	if cue.fade_duration >= 0.0:
		return cue.fade_duration
	return -1.0   # -1 = 交给 set_speed 用全局的 speed_ramp_duration


func _resolve_fade_time(t: float) -> float:
	return fade_duration if t < 0.0 else t


func _set_db(db: float, p: AudioStreamPlayer) -> void:
	p.volume_db = db


func _kill(t: Tween) -> void:
	if t != null and t.is_valid():
		t.kill()


## mp3 / ogg 导入时默认不循环，BGM 基本都要循环，所以这里直接打开资源上的开关。
##
## 改的是**共享资源**：同一首曲子在别处播放也会跟着循环。BGM 场景下这正是想要的，
## 而且只改内存里的实例，不会写回磁盘。要按处不同就在导入面板上设，别用这个字段。
func _apply_loop(stream: AudioStream, loop: bool) -> void:
	for prop in stream.get_property_list():
		if prop["name"] == "loop" and prop["type"] == TYPE_BOOL:
			stream.set("loop", loop)
			return
