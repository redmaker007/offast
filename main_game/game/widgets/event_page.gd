extends PanelContainer
class_name event_page

## 桌面桥段层：点电箱、窗户、接来电时播一段对话。
## （便签不在其中：桌上那本是玩家自己写字的记事本，见 notes_page。
##  电话也不直接接管：点电话先由 caller_page 决定「接来电」还是「拨号」。）
##
## 除了当天的桥段，拨通电话之后那段对话也在这一层播（play_conversation）。
##
## **什么时候播**归当天的天内图管：点物件 → （if 今天播过没有 → 记下）→ 剧情 bubble，
## round_manager 执行那个剧情 bubble 时调 play_conversation()。内容还在 day_plan 里
## （caller / electricbox / window 三格）。
##
## 长相和剧情层是同一套气泡（bubble_view），播放逻辑也共用 conversation_player，
## 所以对话选项的立场增量在这里照样生效——电话里怎么应付 B 派也是表态。
##
## **每天每个物件只播一次**：图上的效果节点把 flag 记进 GameState（"event_caller_day_1"），
## 跟着存档走，读档回来不会又能刷一遍。flag 名见 flag_for()。
##
## 本体是铺满屏的遮罩，所以桥段是模态的；故意不走 WindowManager——
## 它管的是笔记本那种「同一时刻只开一个窗口」，桥段该盖在最上面。

## 一段对话播完、遮罩收起之后发出。天内图在等它才往下走。
signal conversation_finished

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
	SignalBus.story_content_reloaded.connect(_on_content_reloaded)


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
		&"node":
			# 天内图里的桥段：按节点 id 找回同一段（当前语言）。
			return %round_manager.conversation_for_node(_source_id)
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
	conversation_finished.emit()
