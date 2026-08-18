extends Node
class_name round_manager

## 一天的流程调度：剧情 → 上班 → 结算 → 下一天。
##
## 三段的推进条件各不相同，所以不用取模循环，各走各的显式转移：
##   STORY  --story_finished-->        GAME
##   GAME   --day_time_up / 点门-->    RESULT
##   RESULT --玩家点继续-->            下一天 / 被开除 / 通关

## 简单模式：扛过这么多天就算赢。
@export var days_to_win: int = 5

## 一开始有几条命。
@export var max_lives: int = 3

## 一天错几个人就扣一条命。
@export var mistakes_per_life: int = 3

## 每天发几封邮件、点名几个员工。
@export var emails_per_day: int = 7
@export var employees_per_day: int = 3

## 邮件还没读完就去点门时弹的提示。
@export var unfinished_notice: String = "Need to finish all the work first..."

var current_day := 0
var lives := 0
var current_round_employee_name_list = []

var save_id := "round_manager"


func _ready() -> void:
	add_to_group(SaveState.GROUP)
	SignalBus.story_finished.connect(_on_story_finished)
	SignalBus.day_time_up.connect(end_day)
	SignalBus.leave_office_request.connect(_on_leave_office)
	SignalBus.result_confirmed.connect(_on_result_confirmed)


func save_data() -> Dictionary:
	return {
		"current_day": current_day,
		"lives": lives,
		"current_round_employee_name_list": current_round_employee_name_list,
	}


func load_data(d: Dictionary) -> void:
	current_day = d.get("current_day", 0)
	lives = d.get("lives", max_lives)
	current_round_employee_name_list = d.get("current_round_employee_name_list", [])


## 开新局：第 1 天，满血。
func start_game() -> void:
	current_day = 0
	lives = max_lives
	start_next_day()


func start_next_day() -> void:
	current_day += 1
	_change_state(RoundState.Round_State.STORY)


# ── 三段流转 ──────────────────────────────────────────

func _on_story_finished() -> void:
	if RoundState.current_round_state != RoundState.Round_State.STORY:
		return
	_change_state(RoundState.Round_State.GAME)


func _on_leave_office() -> void:
	# 活没干完不许走。判定只看收件箱有没有清空——这是客观的、不泄题的：
	# 「这个人什么都不用做」本来就是常见的正确答案，拿人事表填没填全当条件
	# 等于告诉玩家每个人都有事做。
	if not _work_finished():
		SignalBus.notice_requested.emit(unfinished_notice)
		return
	end_day()


## 今天的活干完了没有。到点自动下班不查这个，只有主动点门才查。
func _work_finished() -> bool:
	return %email_reader.remaining() == 0


## 到点或玩家自己下班。两个入口都可能重复触发，所以先查状态。
func end_day() -> void:
	if RoundState.current_round_state != RoundState.Round_State.GAME:
		return
	_change_state(RoundState.Round_State.RESULT)


func _on_result_confirmed() -> void:
	if RoundState.current_round_state != RoundState.Round_State.RESULT:
		return
	# 被开除优先于通关：最后一天把命扣光了也是被开除。
	if lives <= 0:
		SignalBus.game_over.emit()
		return
	if current_day >= days_to_win:
		SignalBus.game_cleared.emit()
		return
	start_next_day()


func _change_state(rs: RoundState.Round_State) -> void:
	RoundState.current_round_state = rs
	_enter_state(rs)


func _enter_state(rs: RoundState.Round_State) -> void:
	match rs:
		RoundState.Round_State.STORY:
			%day_clock.stop()
		RoundState.Round_State.GAME:
			_begin_workday()
		RoundState.Round_State.RESULT:
			_settle_day()
	SignalBus.round_state_change.emit(rs)


func _begin_workday() -> void:
	# 隔夜的邮件和指令都不留，每天从干净的收件箱开始。
	%email_reader.clear_inbox()
	%instruction_box.clear_box()
	%personnel_manager.begin_day()

	current_round_employee_name_list = %email_generator.get_random_employee_name(employees_per_day)
	for i in range(emails_per_day):
		%email_generator.generate_email(current_round_employee_name_list)

	%day_clock.start()


func _settle_day() -> void:
	%day_clock.stop()
	# 下班时笔记本可能还开着，强制收掉，免得和结算层叠在一起。
	WindowManager.close_current(owner)

	var result: Dictionary = %personnel_manager.grade()
	result["day"] = current_day
	result["days_to_win"] = days_to_win

	if int(result["wrong"]) >= mistakes_per_life:
		lives -= 1
		SignalBus.life_lost.emit(lives)
	result["lives"] = lives

	SignalBus.day_result_ready.emit(result)
