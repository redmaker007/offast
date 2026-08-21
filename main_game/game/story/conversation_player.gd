extends RefCounted
class_name conversation_player

## 把一段 conversation 喂给一个 bubble_view 播完。
##
## 「播到哪、下一条是谁、选项往哪跳、选完加什么数值」都在这里；
## 「一条气泡怎么演」（逐字机、按钮、选项）归 bubble_view。
##
## 剧情层（story_page）和桌面桥段层（event_page）用的是同一套播放逻辑，
## 区别只在于播哪一段、播完之后干什么，所以抽出来一份共用。

## 这一段播完了。
signal finished()

var _view: bubble_view
var _conversation: conversation = null
var _dialogue: dialogue = null
var _index := 0


func _init(view: bubble_view) -> void:
	_view = view
	_view.advance_requested.connect(_on_advance_requested)
	_view.choice_picked.connect(_on_choice_picked)


## 从头播一段。传 null 或空的会立刻发 finished——没写内容不该卡住玩家。
func play(c: conversation) -> void:
	_conversation = c
	if c == null or c.is_empty():
		_finish()
		return
	_enter(c.first())


## 正在播吗。桥段层用它判断「这一段还没播完，别又开一段」。
func is_playing() -> bool:
	return _conversation != null


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
		# 这一段走完了，线性接下一段；没有下一段就整段播完。
		_enter(_conversation.next_after(_dialogue))
		return
	# 条件不成立的气泡整条跳过（`?if ... ?end` 包起来的那些）。
	# 用 while 而不是递归：一段里连着十几条不该播的也不会把栈堆起来。
	while b != null and not b.visible():
		_index += 1
		b = _dialogue.bubble_at(_index)
	if b == null:
		_enter(_conversation.next_after(_dialogue))
		return
	_view.show_bubble(b)


func _on_advance_requested() -> void:
	if _conversation == null:
		return
	_index += 1
	_show_current()


func _on_choice_picked(_index_in_bubble: int, choice: conversation_choice) -> void:
	if _conversation == null:
		return
	# 选项的立场影响在跳转之前结算：跳过去之后 choice 就够不着了。
	if choice != null:
		GameState.apply_effect(choice.effect)
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
	finished.emit()
