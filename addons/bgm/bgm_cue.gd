extends Resource
class_name bgm_cue

## 「某个场景该放什么 BGM」的一行配置，由 bgm_player 按场景路径查表。
##
## 三个字段都可以留空，留空的含义各不相同：
##   stream 留空 —— 不换曲，当前放着的接着放，但速度设置照样生效
##   bpm 留空    —— 不动速度，沿用当前倍率
##   fade 跟随   —— 用播放器上的全局渐变设置


## 渐变开关。INHERIT 用播放器的全局设置，另外两个是这一行单独说了算。
enum Fade { INHERIT, ON, OFF }


@export_group("这一行管哪个场景")

## 从文件系统面板把 .tscn 直接拖进来。
##
## 注意：autoload 持有 PackedScene 引用会让这个场景在**开机时就被加载**
## （连带它的贴图、shader、音频）。场景很大又不想付这份开机成本，
## 就改用下面的 scene_path，那个只是个字符串。
@export var scene: PackedScene

## 直接填路径，或者点右边的文件夹图标挑一个。scene 留空时才会用到这个。
@export_file("*.tscn") var scene_path: String = ""


@export_group("放什么")

## 这个场景放哪首曲子。**留空 = 不换曲**——当前放着的接着放，
## 只有下面的速度设置会生效。
@export var stream: AudioStream

## 循环播放。mp3 导入时默认是不循环的，放完就停，所以这里默认打开。
## 打开会直接改 stream 资源的 loop 属性，见 bgm_player._apply_loop 的说明。
@export var loop: bool = true

## 这一行单独的音量增减，会叠加在播放器的全局 volume_db 上。
@export_range(-60.0, 12.0, 0.1, "suffix:dB") var volume_db: float = 0.0


@export_group("速度")

## 想要的速度。**0 = 不变**（沿用当前倍率）。两种填法：
##   填了 source_bpm（或曲子自带 Bpm）→ 倍率 = bpm ÷ 原速，按真 BPM 语义走
##   两个都没有                        → 这个值直接当倍率用，1.0 就是原速
##
## 注意：引擎没有变速不变调，调速度会连音高一起变（快了变尖，慢了变闷）。
@export var bpm: float = 0.0

## 曲子的原速 BPM。0 = 不知道，此时会去读 stream 自带的 Bpm（mp3 导入面板里能填），
## 还是没有就把上面的 bpm 当倍率用。
@export var source_bpm: float = 0.0


@export_group("渐变")

## 这一行换曲 / 变速时要不要渐变。
@export var fade: Fade = Fade.INHERIT

## 这一行专用的渐变时长（秒）。**负数 = 跟随播放器的全局时长**。
@export var fade_duration: float = -1.0


## 这一行指向的场景路径。拖进来的 scene 优先，其次才是手填的 scene_path。
func target_path() -> String:
	if scene != null and not scene.resource_path.is_empty():
		return scene.resource_path
	return resolve_uid(scene_path)


## Inspector 的文件选择器填进来的可能是 `uid://xxxx` 而不是 `res://...`，
## 而 SceneTransition 比对的是 res:// 路径，不换算就永远匹配不上。
static func resolve_uid(path: String) -> String:
	if not path.begins_with("uid://"):
		return path
	var id := ResourceUID.text_to_id(path)
	if id != ResourceUID.INVALID_ID and ResourceUID.has_id(id):
		return ResourceUID.get_id_path(id)
	return path


## 换算成播放速度倍率。**返回 0 表示这一行不动速度。**
func speed() -> float:
	if bpm <= 0.0:
		return 0.0
	var base := base_bpm()
	if base > 0.0:
		return bpm / base
	return bpm


## 曲子的原速 BPM，不知道就是 0。手填的优先于 stream 自带的元数据。
func base_bpm() -> float:
	if source_bpm > 0.0:
		return source_bpm
	if stream != null:
		var meta: Variant = stream.get("bpm")
		if meta != null and float(meta) > 0.0:
			return float(meta)
	return 0.0
