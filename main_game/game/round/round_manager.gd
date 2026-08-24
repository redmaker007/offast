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

## 每天发几封邮件、抽几个随机员工。
##
## **剧情角色不占这个名额**：剧情信点名的人会自动加进人事表，
## 所以一天的表 = 随机员工 employees_per_day 个 + 当天剧情涉及的人。
@export var emails_per_day: int = 7
@export var employees_per_day: int = 3

## **一天最多能给几个人升职**。升职是稀缺资源，不是想给谁就给谁。
## 0 = 当天一个都不许升；-1 = 不限制。
@export var promotions_per_day: int = 1

## 名额用完还去点「升职」时弹的提示。填翻译 key，里面的 %d 会换成名额数。
@export var promotion_limit_notice: String = "UI_PROMO_LIMIT"

## 邮件还没读完就去点门时弹的提示。填翻译 key（见 locale/ui.csv）或者直接填一句话。
@export var unfinished_notice: String = "UI_UNFINISHED"

## 随机信凑出超额升职时最多重掷几次。掷不出来就认了——
## 名额比可点名的人数还紧的时候，怎么掷都不可能满足。
const REROLL_ATTEMPTS := 8

var current_day := 0
var lives := 0
var current_round_employee_name_list = []

## 当天抽中的随机员工（剧情角色不在里面）。
## 「fire 掉今日所有员工」这类判定要能分清谁是随机的、谁是剧情角色。
var current_random_name_list = []

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
		"current_random_name_list": current_random_name_list,
	}


func load_data(d: Dictionary) -> void:
	current_day = d.get("current_day", 0)
	lives = d.get("lives", max_lives)
	current_round_employee_name_list = d.get("current_round_employee_name_list", [])
	current_random_name_list = d.get("current_random_name_list", [])


## 开新局：第 1 天，满血。
func start_game() -> void:
	current_day = 0
	lives = max_lives
	# 剧情状态和玩法状态一起归零，不然新一局会接着上一局的分数往下算。
	GameState.reset()
	# 员工权限的初值来自档案（鲍勃 1 级、米拉 3 级……），之后靠 promotion 往上走。
	GameState.seed_levels(%story_book.world)
	# 电话号码每局重摇一次，防止玩家背号码。
	GameState.seed_caller_numbers(%story_book.world)
	# 电脑密码同理：抄在记事本上的那串每局都不一样。
	GameState.seed_account_passwords(%story_book.world)
	# 摇完了才广播：记事本要照着这一局的账号密码印第 1 页。
	SignalBus.game_started.emit()
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
		SignalBus.notice_requested.emit(tr(unfinished_notice))
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

	# **电脑不会隔夜自动锁上**：第 1 天敲完密码就一直登着。
	# 想换号（后面几天拿到别人的账户）得自己去选择页 Sign out。
	var plan: day_plan = %story_book.plan_for(current_day)

	# 剧情角色进表，但**不占随机员工的名额**：随机的永远抽满 employees_per_day 个。
	# 条件不成立的剧情信当天根本不存在，所以点名、判分都不该算上它点的人。
	GameState.day = current_day
	var mails: Array = _mails_for_today(plan)

	var story_names: Array = _story_names(plan, mails)
	var filler_names: Array = %email_generator.get_random_employee_name(
		employees_per_day, story_names)
	current_random_name_list = filler_names
	current_round_employee_name_list = story_names + filler_names
	%personnel_manager.begin_day(_ungraded_names(mails, story_names))

	# **随机信先发，剧情信压在后面**：收件箱是先进先出的，所以玩家先处理一堆
	# 例行公事，剧情信才出现——「今天这封不一样」才有分量。
	#
	# 顺带把冲突规则也理顺了：等级高的盖低的、同级后来的盖先来的，所以后发的
	# 剧情信一定盖得住前面的随机信。第二天班纳那句「别管之前的指示」就是照字面生效的。
	var filler_count := emails_per_day
	if plan != null and plan.filler_emails >= 0:
		filler_count = plan.filler_emails
	var exclude: Array = plan.filler_exclude if plan != null else []
	if not filler_names.is_empty():
		for i in range(filler_count):
			%email_generator.generate_email(filler_names, exclude)

	for mail_def in mails:
		if mail_def.targets_all_random():
			# 「把前面提到的员工全部 fire 掉」：展开成一人一封，
			# 这样冲突规则、判分、日志都不用为它开特例。
			for name in filler_names:
				SignalBus.send_email.emit(mail_def.make_email(StringName(name)))
		else:
			SignalBus.send_email.emit(mail_def.make_email())

	# **人事表上只留今天真的有事要办的人**：随机员工是先抽名字、再按名字发信的，
	# 信少于人的日子（第 4 天两封、第 5 天一封都没有）就会剩下几个谁都没提过的人，
	# 摆在表上纯属噪音——玩家得挨个确认「这人是不是我漏读了什么」。
	# 剧情角色不在此列：他们是作者点名进表的，本来就可能「什么都不用做」。
	current_random_name_list = _with_instructions(filler_names)
	current_round_employee_name_list = story_names + current_random_name_list

	# 随机信要是凑出了超过名额的升职，这一天就永远拿不到满分了——
	# 玩家填不进去的答案不该出现在标准答案里。整批重掷（还没人读过，重掷是安全的）。
	# 剧情信里作者故意让升职超额是另一回事，那是设计好的两难，所以只重掷随机信。
	if not _promotions_within_limit() and not filler_names.is_empty():
		for attempt in range(REROLL_ATTEMPTS):
			_reroll_fillers(plan, filler_names, filler_count)
			if _promotions_within_limit():
				break
		# 重掷换了一批信，收到指令的人跟着变了，表得按新的那批重铺。
		current_random_name_list = _with_instructions(filler_names)
		current_round_employee_name_list = story_names + current_random_name_list

	%day_clock.start()


## 这批随机员工里今天真的收到指令的那些（顺序不变）。
## 查的是 instruction_box——它听的是「信发出去了」，不是「玩家读了」，
## 所以开工那一刻就是全的。
func _with_instructions(names: Array) -> Array:
	var truth: Dictionary = %instruction_box.get_all()
	var kept: Array = []
	for n in names:
		if truth.has(String(n)):
			kept.append(n)
	return kept


## 今天真正会发出去的剧情信：`if=` 条件不成立的直接不算数。
func _mails_for_today(plan: day_plan) -> Array:
	var out: Array = []
	if plan == null:
		return out
	for mail_def in plan.scripted_emails:
		if mail_def != null and mail_def.should_send():
			out.append(mail_def)
	return out


## 当天要进人事表的剧情角色：day_plan 的 roster 里写的，加上剧情信**点名下令**的人。
## 两边合起来是为了少写一处——信里写了 order=raise:Mira，就不用再去 roster 补一遍。
##
## `about=` 不算：那只是「这封信里点开谁的档案」，提到某人不等于要处理他。
func _story_names(plan: day_plan, mails: Array) -> Array:
	var names: Array = []
	if plan == null:
		return names
	for n in plan.story_roster:
		var s_name := String(n)
		if not s_name.is_empty() and not names.has(s_name):
			names.append(s_name)
	# 带条件的那些：条件不成立就不上表。第四天主角自己那一行就是这么来的——
	# 只有罗德里克真的暗示了「你也该为自己想想」，给自己批 promotion 才是个选项。
	for rule in plan.conditional_roster:
		if rule == null or String(rule.employee_name).is_empty():
			continue
		var c_name := String(rule.employee_name)
		if names.has(c_name) or not story_condition.eval(rule.condition):
			continue
		names.append(c_name)
	for mail_def in mails:
		if mail_def.targets_all_random():
			continue
		var s_name := String(mail_def.target_employee)
		if not s_name.is_empty() and not names.has(s_name):
			names.append(s_name)
	return names


## 当天不判对错的人：只被 graded=no 的信提到的角色，以及主角自己。
## 同一个人要是还被一封判分的信点名（第三天的瑞克），那还是要判分的。
func _ungraded_names(mails: Array, story_names: Array) -> Array:
	var ungraded: Array = [String(GameState.SELF)]

	var graded_targets: Array = []
	for mail_def in mails:
		if mail_def.graded and mail_def.has_order():
			graded_targets.append(String(mail_def.target_employee))

	for name in story_names:
		if not graded_targets.has(name) and not ungraded.has(name):
			ungraded.append(name)
	return ungraded


## 标准答案里要求升职的人数有没有超过当天名额。
func _promotions_within_limit() -> bool:
	if promotions_per_day < 0:
		return true
	var wanted := 0
	for name in %instruction_box.get_all():
		if bool(%instruction_box.get_all()[name].has_promotion):
			wanted += 1
	return wanted <= promotions_per_day


## 把当天的信整批重发一次（剧情信照旧，随机信重掷）。顺序和 _begin_workday 一致：
## 随机信在前，剧情信在后。
func _reroll_fillers(plan: day_plan, filler_names: Array, filler_count: int) -> void:
	%email_reader.clear_inbox()
	%instruction_box.clear_box()
	for i in range(filler_count):
		%email_generator.generate_email(filler_names, plan.filler_exclude if plan != null else [])
	for mail_def in _mails_for_today(plan):
		if mail_def.targets_all_random():
			for name in filler_names:
				SignalBus.send_email.emit(mail_def.make_email(StringName(name)))
		else:
			SignalBus.send_email.emit(mail_def.make_email())


func _settle_day() -> void:
	%day_clock.stop()
	# 下班时笔记本可能还开着，强制收掉，免得和结算层叠在一起。
	WindowManager.close_current(owner)

	var result: Dictionary = %personnel_manager.grade()
	result["day"] = current_day
	result["days_to_win"] = days_to_win

	_record_day(result.get("rows", []))

	if int(result["wrong"]) >= mistakes_per_life:
		lives -= 1
		SignalBus.life_lost.emit(lives)
	result["lives"] = lives

	SignalBus.day_result_ready.emit(result)


## 把今天的人事决定记进日志，并把批出去的 promotion 落实成权限。
##
## **这里不再自动加结局分**：设计里每一分都写在当天的「逻辑项」里
## （"fire 掉今日所有员工 → A+2"），二期由 .story 的 [score] 块接管。
## 日志得留着——结局前要摊给玩家看，也是那些条件判定的数据来源。
func _record_day(rows: Array) -> void:
	for row in rows:
		var entry: Dictionary = row.duplicate()
		# 标一下这一行是不是随机员工：「fire 掉今日所有员工」判的是随机那批。
		entry["random"] = current_random_name_list.has(str(row.get("employee", "")))
		GameState.log_personnel(current_day, entry)
		# 批出去的 promotion 会把对方的权限抬一级。鲍勃 1→4 级就是这么攒的。
		if bool(row.get("actual", {}).get("Promotion", false)):
			GameState.promote(StringName(str(row.get("employee", ""))))

	# 日志写完了才判 [score]——那些规则问的就是「你今天到底做了什么」。
	_apply_score_rules()


## 当天的「逻辑项」：条件成立就加对应的结局分。按写的顺序判，互不排斥。
func _apply_score_rules() -> void:
	var plan: day_plan = %story_book.plan_for(current_day)
	if plan == null:
		return
	for rule in plan.score_rules:
		if rule != null and story_condition.eval(rule.condition):
			GameState.apply_effect(rule.effect)
