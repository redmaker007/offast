extends PanelContainer
class_name event_page

## 桌面桥段层：点电箱、窗户、接来电时播一段对话。
## （便签不在其中：桌上那本是玩家自己写字的记事本，见 notes_page。
##  电话也不直接接管：点电话先由 caller_page 决定「接来电」还是「拨号」。）
##
## 除了当天的桥段，拨通电话之后那段对话也在这一层播（play_conversation）。
##
## 内容全在 day_plan 里（caller / electricbox / window 三格），
## 哪一格留空点了就没反应——和加剧情系统之前的行为一致，不会突然弹个空框。
##
## 长相和剧情层是同一套气泡（bubble_view），播放逻辑也共用 conversation_player，
## 所以对话选项的立场增量在这里照样生效——电话里怎么应付 B 派也是表态。
##
## **每天每个物件只播一次**：flag 记在 GameState 里（"event_caller_day_1"），
## 跟着存档走，读档回来不会又能刷一遍。
##
## 本体是铺满屏的遮罩，所以桥段是模态的；故意不走 WindowManager——
## 它管的是笔记本那种「同一时刻只开一个窗口」，桥段该盖在最上面。

## 桌面物件的信号名 -> day_plan 里的哪一格。
## 自己接管的桌面物件。电话不在里面：那个归 caller_page 先过一道手。
const EVENTS := {
	"open_electricbox_request": &"electricbox",
}

var _player: conversation_player
var _playing := false

## 正在演的是哪一段：桥段记 key（"caller"/"electricbox"/…），
## 通话记联系人名。换语言时靠它把同一段的另一种语言找回来。
var _source_kind := &""
var _source_id := &""


func _ready() -> void:
	visible = false
	_player = conversation_player.new(%event_bubble)
	_player.finished.connect(_on_finished)
	for signal_name in EVENTS:
		SignalBus.connect(signal_name, _on_event_requested.bind(EVENTS[signal_name]))
	SignalBus.story_content_reloaded.connect(_on_content_reloaded)


func _on_event_requested(key: StringName) -> void:
	try_play_day_event(key)


## 播当天这个物件的桥段。**返回有没有真的播起来**——
## caller_page 靠这个判断「今天还有没有没接的来电」，没有才弹拨号盘。
func try_play_day_event(key: StringName) -> bool:
	if _playing:
		return false
	# flag 按「第几天」记，内容按「用第几天的剧本」取：有了关卡图，两者可以不一样。
	var day: int = %round_manager.current_day
	var c: conversation = %story_book.event_for(%round_manager.current_plan_day(), key)
	if c == null or c.is_empty():
		return false

	# 默认每天每个物件只播一次。电箱是例外（repeat=yes）：
	# 没钥匙时点开只看到「锁着」，拿到钥匙当天还得能再开一次。
	var plan: day_plan = %round_manager.current_plan()
	var repeatable: bool = plan != null and plan.repeats(key)
	if not repeatable and GameState.has_flag(flag_for(key, day)):
		return false
	GameState.set_flag(flag_for(key, day))

	play_conversation(c, &"event", key)
	return true


## 播任意一段对话（拨通电话之后用的就是这个）。
## kind/id 是给「换语言时找回同一段」用的，不传就只是不支持中途换语言。
func play_conversation(c: conversation, kind := &"", id := &"") -> void:
	if _playing or c == null or c.is_empty():
		return
	_source_kind = kind
	_source_id = id
	_playing = true
	visible = true
	_player.play(c)


## 换语言：把正在演的这一段换成另一种语言的同一段，位置不变。
func _on_content_reloaded(_locale: String) -> void:
	if not _playing:
		return
	var c := _current_source()
	if c != null:
		_player.resume(c, _player.position())


## 正在演的那一段，在**当前语言**的内容里对应的是哪一份。
func _current_source() -> conversation:
	match _source_kind:
		&"event":
			return %story_book.event_for(%round_manager.current_plan_day(), _source_id)
		&"call":
			var who: contact = %story_book.contact_by_name(_source_id)
			return who.call if who != null else null
	return null


## 「今天这个物件已经播过了」的 flag 名。测试要能拼出同一个名字。
static func flag_for(key: StringName, day: int) -> StringName:
	return StringName("event_%s_day_%d" % [key, day])


func _on_finished() -> void:
	if not _playing:
		return
	_playing = false
	_source_kind = &""
	_source_id = &""
	visible = false
