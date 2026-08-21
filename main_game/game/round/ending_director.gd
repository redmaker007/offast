extends Node
class_name ending_director

## 结局调度：第 5 天扛过去之后决定放哪个结局，并把「日志 → 结局对话 → 结局卡」
## 这三步串起来。
##
## 五个结局：
##   A 瑞克反超，把主角和一批老员工清掉
##   B 主角给自己违规 promo，被公司开掉
##   C 两派维持制衡，主角和米拉鲍勃一起被清
##   D 主角拿到 5 级权限，反手 fire 掉两个头目
##   E 失误太多被开除（三条命掉光，随时可能发生）
##
## 判定规则写在 world.story 的 [ending] 块里，按顺序判、第一条成立的算数，
## 都不成立走兜底 C。**分数只决定第五天收到哪封信，第五天的操作才决定结局**。



## 正在走「日志 → 对话 → 卡」这个流程。story_finished 是全局信号，
## 得靠它区分「这是结局对话播完了」还是「哪天的开场剧情播完了」。
var _pending: StringName = &""
var _awaiting_story := false


func _ready() -> void:
	SignalBus.game_cleared.connect(_on_game_cleared)
	SignalBus.game_over.connect(_on_game_over)
	SignalBus.log_review_finished.connect(_on_log_review_finished)
	SignalBus.story_finished.connect(_on_story_finished)


## 结局文案在内容文件里（world.story 的 [ending_text X]），跟着语言走。
func def_for(id: StringName) -> ending_def:
	var world: world_book = %story_book.world
	return world.ending_text(id) if world != null else null


## 都不成立时走哪个结局。设计里是 C（两派维持制衡）。
@export var fallback_ending: StringName = &"C"


func _on_game_cleared() -> void:
	_pending = _decide()
	# 先摊日志：这五天的每一个决定，看完再给结局。
	SignalBus.log_review_requested.emit()


## 按 world.story 里那张规则表定结局。
func _decide() -> StringName:
	var world: world_book = %story_book.world
	if world != null:
		for rule in world.ending_rules:
			if rule != null and story_condition.eval(rule.condition):
				return rule.ending
	return fallback_ending


func _on_game_over() -> void:
	_pending = &""
	_awaiting_story = false
	SignalBus.ending_ready.emit(&"E")


func _on_log_review_finished() -> void:
	if String(_pending).is_empty():
		return
	var d := def_for(_pending)
	if d == null or d.story == null or d.story.is_empty():
		_reveal()
		return
	# 借剧情层来播：结局对话和开场剧情长得就该一样。
	# STORY 段之外 round_manager 不理会 story_finished，所以不会被误当成"该开工了"。
	_awaiting_story = true
	%story_page.visible = true
	%story_page.play(d.story)


func _on_story_finished() -> void:
	if not _awaiting_story:
		return
	_awaiting_story = false
	%story_page.visible = false
	_reveal()


func _reveal() -> void:
	var id := _pending
	_pending = &""
	SignalBus.ending_ready.emit(id)
