extends PanelContainer

## 剧情层：每天开场的全屏覆盖。STORY 段显示，其余时候隐藏。
##
## 职责是「播完当天那段 conversation」，播完发 story_finished，round_manager 收到就开工。
## 具体的播放逻辑（下一条是谁、选项往哪跳、选完加什么数值）在 conversation_player 里，
## 和桌面桥段层（event_page）共用一份。
##
## 内容只有一个来源：story_book 里当天那份 day_plan 的 story（由 story/days/day_N.story
## 导入而来）。没配的天就直接跳过剧情开工。
##
## 播放进度不进存档：STORY 段中途回菜单再读档，这一天的剧情从头播一遍。
## 剧情是每天开场的固定内容，重看一遍不会丢任何东西，不值得为它加存档字段。

var _player: conversation_player


func _ready() -> void:
	visible = false
	_player = conversation_player.new(%bubble_view)
	_player.finished.connect(_on_player_finished)
	SignalBus.round_state_change.connect(_on_round_state_change)
	SignalBus.game_restored.connect(_refresh)
	SignalBus.story_content_reloaded.connect(_on_content_reloaded)


func _on_round_state_change(_rs) -> void:
	_refresh()


func _refresh() -> void:
	# RoundState.current_round_state 是无类型的 var，用 := 推不出 bool，得写死类型。
	var showing: bool = RoundState.current_round_state == RoundState.Round_State.STORY
	visible = showing
	if showing:
		play(%round_manager.current_story())


## 换语言之后内容整套换了一份：**正在演的那一句要就地换过来**，
## 不能等下一句才生效，也不该从头重播。
func _on_content_reloaded(_locale: String) -> void:
	if not visible or not _player.is_playing():
		return
	_player.resume(%round_manager.current_story(), _player.position())


## 第 day 天的剧本（从 1 开始）该播哪段剧情。没写就是 null，
## conversation_player 收到 null 会立刻发 finished，不卡玩家。
func conversation_for_day(day: int) -> conversation:
	var plan: day_plan = %story_book.plan_for(day)
	return plan.story if plan != null else null


## 从头播一段剧情。传 null 或空的会直接结束（发 story_finished）。
## 平时由 _refresh() 按天调，结局层也会直接喂一段进来。
func play(c: conversation) -> void:
	_player.play(c)


func _on_player_finished() -> void:
	SignalBus.story_finished.emit()
