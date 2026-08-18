extends PanelContainer

## 剧情层：每天开场的全屏覆盖。STORY 段显示，其余时候隐藏。
##
## 职责是「播完当天那段 conversation」：一条气泡一条喂给 bubble_view，
## 全部走完发 story_finished，round_manager 收到就开工。
##
## 怎么演一条气泡（逐字机、按钮、选项）归 bubble_view；
## 播到哪一段、下一条是谁、选项往哪跳，归这里。
##
## 播放进度不进存档：STORY 段中途回菜单再读档，这一天的剧情从头播一遍。
## 剧情是每天开场的固定内容，重看一遍不会丢任何东西，不值得为它加存档字段。

## 第几天播哪段剧情。**下标 0 是第 1 天**。
## 没配到的天（数组不够长、或者那一格是空的）用下面的 fallback。
@export var by_day: Array[conversation] = []

## 兜底剧情。by_day 里没有对应的天时用它。
## 连它都留空的话，STORY 段会立刻结束直接开工——开发期没写剧情时就是这样。
@export var fallback: conversation

var _conversation: conversation = null
var _dialogue: dialogue = null
var _index := 0


func _ready() -> void:
	visible = false
	SignalBus.round_state_change.connect(_on_round_state_change)
	SignalBus.game_restored.connect(_refresh)
	%bubble_view.advance_requested.connect(_on_advance_requested)
	%bubble_view.choice_picked.connect(_on_choice_picked)


func _on_round_state_change(_rs) -> void:
	_refresh()


func _refresh() -> void:
	# RoundState.current_round_state 是无类型的 var，用 := 推不出 bool，得写死类型。
	var showing: bool = RoundState.current_round_state == RoundState.Round_State.STORY
	visible = showing
	if showing:
		play(conversation_for_day(%round_manager.current_day))


## 第 day 天（从 1 开始）该播哪段剧情。
func conversation_for_day(day: int) -> conversation:
	var i := day - 1
	if i >= 0 and i < by_day.size() and by_day[i] != null:
		return by_day[i]
	return fallback


# ── 播放 ────────────────────────────────────────────────

## 从头播一段剧情。传 null 或空的会直接结束（发 story_finished）。
## 平时由 _refresh() 按天调，也可以从外面直接喂一段进来。
func play(c: conversation) -> void:
	_conversation = c
	if c == null or c.is_empty():
		# 没写剧情就别卡着玩家，直接进入上班。
		_finish()
		return
	_enter(c.first())


## 进入一段 dialogue，从它第一条气泡开始。传 null 就是这段剧情播完了。
func _enter(d: dialogue) -> void:
	_dialogue = d
	_index = 0
	if d == null:
		_finish()
		return
	_show_current()


func _show_current() -> void:
	var b: conversation_bubble = _dialogue.bubble_at(_index)
	if b == null:
		# 这一段走完了，线性接下一段；没有下一段就整段剧情结束。
		_enter(_conversation.next_after(_dialogue))
		return
	%bubble_view.show_bubble(b)


func _on_advance_requested() -> void:
	_index += 1
	_show_current()


func _on_choice_picked(_index_in_bubble: int, choice: conversation_choice) -> void:
	if choice != null and choice.jumps():
		var target := _conversation.find(choice.goto)
		if target != null:
			_enter(target)
			return
		# goto 写错了不崩，退回线性继续，顺手提醒一句。
		push_warning("选项的 goto 找不到对应的 dialogue：%s" % choice.goto)
	_on_advance_requested()


func _finish() -> void:
	_conversation = null
	_dialogue = null
	_index = 0
	SignalBus.story_finished.emit()
