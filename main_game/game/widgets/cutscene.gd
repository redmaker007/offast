extends Node
class_name cutscene

## 动画（时停）：play() 之后的 duration 秒里锁住交互，时间到了自己放开。
## 现在只是个空壳，画面上演什么以后接 started / finished / cancelled 来做。
##
## 播放期间：
##   - RoundState.is_interactive() 是 false：桌面物件点不了、不发光，上班时钟也停。
##   - 右上角的齿轮还能点。设置面板开着时计时暂停，关掉接着走。
##   - 回主菜单（场景被挂起）就当这次没播过：解锁、计时清零、发 cancelled。
##     回菜单前的存盘本来就不存锁，所以存档里也是动画开始前的样子。
##
## 直接把这个脚本挂到场景里的一个空 Node 上即可。

## 开始播放时发出。
signal started
## 播满 duration 秒、交互已经放开之后发出。
signal finished
## 播到一半被打断（回主菜单）时发出，交互已经放开。
## 动画改过的东西要在这里退回开始前的样子。
signal cancelled

## 动画时间（秒）：时停多久，这段时间里不能交互。
@export var duration: float = 1.0

## 暂停计时看的是这个面板开没开着。
const SETTINGS_PANEL := "res://main_game/menu/settings_panel.tscn"

var _playing := false
var _elapsed := 0.0


func _ready() -> void:
	set_process(false)
	SignalBus.game_suspended.connect(_on_game_suspended)


func _exit_tree() -> void:
	# 场景被销毁时别把锁留在 RoundState 上，不然下一局物件全点不了。
	if _playing:
		_stop()


## 开始播放。已经在播就不重来。
func play() -> void:
	if _playing:
		return
	_playing = true
	_elapsed = 0.0
	RoundState.lock_interaction(self)
	set_process(true)
	started.emit()


## 打断播放，退回开始前。没在播就什么都不做。
func cancel() -> void:
	if not _playing:
		return
	_stop()
	cancelled.emit()


func is_playing() -> bool:
	return _playing


## 已经播了多少秒（暂停的时间不算）。
func get_elapsed() -> float:
	return _elapsed


## 设置面板开着就暂停。
func is_paused() -> bool:
	var w := WindowManager.get_current(_scene_root())
	return w != null and w.scene_file_path == SETTINGS_PANEL


func _process(delta: float) -> void:
	if is_paused():
		return
	_elapsed += delta
	if _elapsed < duration:
		return
	_stop()
	finished.emit()


func _stop() -> void:
	_playing = false
	_elapsed = 0.0
	set_process(false)
	RoundState.unlock_interaction(self)


func _on_game_suspended() -> void:
	cancel()


## 所在场景的根，WindowManager 按它分开记每个场景的窗口。
## 运行时 add_child 出来的没有 owner：借父节点的，父节点自己就是场景根时用父节点。
func _scene_root() -> Node:
	if owner:
		return owner
	var p := get_parent()
	return p.owner if p.owner else p
