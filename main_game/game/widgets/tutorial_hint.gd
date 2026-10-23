extends Node
class_name tutorial_hint

## 新手提示：挂在可互动的东西下面（clickable_item 物件 / Button 按钮），
## 告诉玩家「这个东西是干嘛的」。
##
## 打开时把 text 用剧情那套对话气泡（bubble_view）说出来——现在借的是
## notice_dialog 那一份，所以配色、逐字机、打字音效和每天开场的剧情是同一套。
## 玩家真的去点了父节点，就说明看懂了，提示自己关掉。
##
## 直接把这个脚本挂到可互动节点下面的一个空 Node 上即可。

## 打开 / 关掉时发出，以后的聚光灯之类跟着走的东西接这两个。
signal opened
signal closed

## 一开始就开着吗。开着的提示等第一次进上班段（物件能点了）才说出来——
## 剧情段说的话会和剧情气泡叠在一起。
@export var start_enabled: bool = false

## 每次打开时说的话。填翻译 key（见 locale/ui.csv）或者直接填一句话。
## **建议填 key**：句子本身放进 ui.csv，场景里只留一个 key，
## 编辑器重存场景把这行抹掉时也只丢一个 key，不丢文案。
@export_multiline var text: String = ""

var _open := false


func _ready() -> void:
	var p := get_parent()
	if p is clickable_item:
		p.clicked.connect(close)
	elif p is BaseButton:
		p.pressed.connect(close)
	else:
		push_warning("tutorial_hint 要挂在 clickable_item 或 Button 下面（节点：%s）" % get_path())

	if start_enabled:
		_open_when_interactive()


## 打开并把 text 说一遍。已经开着就不重复说。
func open() -> void:
	if _open:
		return
	_open = true
	opened.emit()
	if not text.is_empty():
		SignalBus.notice_requested.emit(tr(text))


func close() -> void:
	if not _open:
		return
	_open = false
	closed.emit()


func is_open() -> bool:
	return _open


func _open_when_interactive() -> void:
	if RoundState.is_interactive():
		# 等这一帧别的节点都 _ready 完，notice_dialog 才接得住信号。
		open.call_deferred()
		return
	SignalBus.round_state_change.connect(_on_round_state_change)


func _on_round_state_change(_rs) -> void:
	if not RoundState.is_interactive():
		return
	SignalBus.round_state_change.disconnect(_on_round_state_change)
	open()
