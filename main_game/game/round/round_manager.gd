extends Node
class_name round_manager

## 一天的流程调度：剧情 → 上班 → 结算 → 下一天。
##
## 三段的推进条件各不相同，所以不用取模循环，各走各的显式转移：
## **流程全由关卡图决定**（res://levels/main.level.json，设计见 docs/level_engine.md）：
##   - 外层（level_runner）：下一天是哪一天、什么时候通关、走哪个结局。
##   - 天内（day_runner）：一天里先播什么、点哪个物件发生什么、怎么下班。
## 这里是天内图的 host：图走到剧情、发信、视窗、下班、结算这些要碰界面的元件时，
## 由这里去执行（run_step），执行完告诉图接着走。
##
## RoundState 的三段（STORY / GAME / RESULT）还在，现在是「画面处在哪种模式」：
## 开场剧情 bubble 进 STORY、进自由环节是 GAME、下班元件进 RESULT。

## 读哪一份关卡。
const LEVEL_NAME := "main"

## 「第 N 天 / 共 M 天」里的 M，开局时从关卡图算出来。有分支时只是个参考值。
var days_to_win: int = 0

## 一开始有几条命，来自关卡图的背景设定。
var max_lives: int = 3

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

## 外层关卡图的解释器。关卡有错时 is_valid() 为假，不让开局。
var level: level_runner

## 当天天内图的解释器。
var day: day_runner

## 图在等哪个界面事件（run_step 返回「要等」之后）：
## "story" 开场剧情、"ending_story" 结局对话、"event" 桥段、"result" 结算确认、"log" 看完日志。
var _waiting := ""

## 下班元件算好的当天结果，结算画面元件拿去显示。
var _last_result: Dictionary = {}

## 节点里的文字 → conversation / email_def（按语言缓存）。
var content := level_content.new()


func _ready() -> void:
	add_to_group(SaveState.GROUP)
	level = level_runner.open(LEVEL_NAME)
	if level.is_valid():
		max_lives = level.lives()
		days_to_win = level.total_days()
	else:
		push_error("关卡 %s 有错，不能开局：\n%s" % [LEVEL_NAME, level.describe_errors()])
	day = day_runner.new()
	day.finished.connect(_on_day_finished)
	SignalBus.object_clicked.connect(_on_object_clicked)
	SignalBus.day_time_up.connect(end_day)
	SignalBus.story_finished.connect(_on_story_finished)
	SignalBus.result_confirmed.connect(_on_result_confirmed)
	SignalBus.log_review_finished.connect(_on_log_review_finished)
	SignalBus.game_restored.connect(_on_game_restored)
	%event_page.conversation_finished.connect(_on_event_finished)


func save_data() -> Dictionary:
	return {
		"current_day": current_day,
		"lives": lives,
		"current_round_employee_name_list": current_round_employee_name_list,
		"current_random_name_list": current_random_name_list,
		"level": level.save_data() if level != null else {},
		"day": day.save_data() if day != null else {},
		"waiting": _waiting,
	}


func load_data(d: Dictionary) -> void:
	current_day = d.get("current_day", 0)
	lives = d.get("lives", max_lives)
	current_round_employee_name_list = d.get("current_round_employee_name_list", [])
	current_random_name_list = d.get("current_random_name_list", [])
	if level != null:
		level.load_data(d.get("level", {}), current_day)
		var n := level.current_node()
		if n != null and n.body != null:
			day.attach(n.body, self)
			day.load_data(d.get("day", {}))
	_waiting = str(d.get("waiting", ""))


## 开新局：第 1 天，满血。关卡图有错就不开，把原因弹出来。
func start_game() -> void:
	if level == null or not level.is_valid():
		var why := level.describe_errors() if level != null else "没有关卡"
		SignalBus.notice_requested.emit(tr("UI_LEVEL_INVALID") + "\n" + why)
		return
	level.start()
	current_day = level.day
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
	_start_day()


# ── 外层：一天接一天 ────────────────────────────────────

## 从当前天节点的天内图开头跑起。
func _start_day() -> void:
	var n := level.current_node()
	if n == null or n.body == null:
		push_error("关卡图当前节点「%s」没有天内图" % level.current)
		return
	GameState.day = current_day
	_waiting = ""
	day.start(n.body, self)


## 测试 / 调试用：换掉今天的天内图（比如临时换了剧本，重新转一遍）。
## 不从头重跑：图停在哪个节点就在新图的同名节点上接着走——转换器生成的节点 id 是固定的。
func replace_day_body(body: flow_graph) -> void:
	var n := level.current_node()
	if n == null:
		return
	n.body = body
	content.clear()
	day.attach(body, self)


## 天内图走到了天结束：问外层要下一天。
func _on_day_finished() -> void:
	# 结局天走完就是整局结束，停在结局卡上。
	if level.is_ending():
		return
	# 被开除优先于通关：最后一天把命扣光了也是被开除。
	if lives <= 0:
		level.fire()
		current_day = level.day
		SignalBus.game_over.emit()
		_start_day()
		return
	if level.advance() == null:
		push_error("关卡图走不到下一天（见上一条报错），停在第 %d 天" % current_day)
		return
	current_day = level.day
	# 走到结局天就是通关：结局天自己的天内图会摊日志、播结局对话、出结局卡。
	if level.is_ending():
		SignalBus.game_cleared.emit()
	_start_day()


# ── 天内：玩家的输入和界面事件 ──────────────────────────

func _on_object_clicked(object_id: StringName) -> void:
	day.click(String(object_id))


## 到点（day_clock 发 day_time_up）。
func end_day() -> void:
	day.time_up()


func _on_story_finished() -> void:
	match _waiting:
		"story":
			_resume()
		"ending_story":
			%story_page.visible = false
			_resume()


func _on_event_finished() -> void:
	if _waiting == "event":
		_resume()


func _on_result_confirmed() -> void:
	if _waiting == "result":
		_resume()


func _on_log_review_finished() -> void:
	if _waiting == "log":
		_resume()


func _resume() -> void:
	_waiting = ""
	day.step_done()


## 读档回来：存盘时要是停在强制链中间（比如桥段播到一半），不接着播，
## 退回链开始前的那个自由环节。开场剧情和结算画面照原样接着等。
func _on_game_restored() -> void:
	if day.mode == day_runner.CHAIN and _waiting in ["", "event"]:
		day.abort_chain()
		_waiting = ""


# ── 天内图的 host：执行各个元件 ─────────────────────────

## 进入自由环节：画面切到上班模式。一天里第一次进来才开钟（从强制链回来不重开）。
func enter_free_play(_n: flow_node) -> void:
	if RoundState.current_round_state != RoundState.Round_State.GAME:
		_change_state(RoundState.Round_State.GAME)


## 执行一个强制元件。返回真 = 要等界面事件，等到了再 _resume()。
func run_step(n: flow_node) -> bool:
	match n.type:
		"story_bubble":
			return _run_story(n)
		"send_mail":
			_send_mails(content.plan_for_mail(n))
		"window_bubble":
			_open_window(str(n.props.get("object", "")))
		"clock_out":
			_clock_out()
		"show_result":
			_waiting = "result"
			SignalBus.day_result_ready.emit(_last_result)
			return true
		"show_log":
			_waiting = "log"
			SignalBus.log_review_requested.emit()
			return true
		"show_ending":
			SignalBus.ending_ready.emit(StringName(str(n.props.get("ending", ""))))
		_:
			push_warning("round_manager 不会执行元件「%s」（%s），跳过" % [n.type, n.id])
	return false


## 剧情 bubble，按 layer 放在不同的层上播：
##   notice  一句话提示框（「活还没干完」）
##   story   全屏剧情层：当天开场剧情（进 STORY 模式），或者结局对话（source.ending）
##   event   桌面桥段层（电话、电箱……）
## 返回「还在等」——剧情是空的会同步播完（已经 _resume 过了），那时就不用等了。
func _run_story(n: flow_node) -> bool:
	match str(n.props.get("layer", "event")):
		"notice":
			SignalBus.notice_requested.emit(level_doc.loc_text(n.props.get("script", "")))
			return false
		"story":
			if n.props.has("source"):
				var c := _ending_story(n)
				if c == null or c.is_empty():
					return false
				# 借剧情层来播：结局对话和开场剧情长得就该一样。
				_waiting = "ending_story"
				%story_page.visible = true
				%story_page.play(c)
				return _waiting == "ending_story"
			# 开场剧情：进 STORY 模式，story_page 问 current_story() 拿对话来播。
			_waiting = "story"
			_change_state(RoundState.Round_State.STORY)
			return _waiting == "story"
		_:
			var c := content.conversation_for(n)
			if c == null or c.is_empty():
				return false
			_waiting = "event"
			%event_page.play_conversation(c, &"node", StringName(n.id))
			return _waiting == "event"


## 剧情层现在该播的那一段（当前语言）：图正停在的那个剧情 bubble。换语言时 story_page 也问这里。
func current_story() -> conversation:
	if day == null or day.graph == null:
		return null
	var n := day.graph.node(day.current)
	if n == null or n.type != "story_bubble":
		return null
	if n.props.has("source"):
		return _ending_story(n)
	return content.conversation_for(n)


## 桥段层换语言时按节点 id 找回同一段。
func conversation_for_node(id: StringName) -> conversation:
	if day == null or day.graph == null:
		return null
	return content.conversation_for(day.graph.node(String(id)))


## 按 id 找剧情信的定义（当前语言）：先在关卡的发信节点里找，找不到再问 story_book。
func mail_def(id: StringName) -> email_def:
	var def := content.mail_def(level.doc if level != null else null, id)
	return def if def != null else %story_book.mail_def(id)


## 结局对话还在 world.story 里（世界表迁移之前）。
func _ending_story(n: flow_node) -> conversation:
	var src: Dictionary = n.props.get("source", {})
	var d: ending_def = %ending_director.def_for(StringName(str(src.get("ending", ""))))
	return d.story if d != null else null


## 视窗 bubble：打开物件自带的弹窗。第 3 阶段房间数据化之后，物件开什么窗写在世界表里。
func _open_window(object_id: String) -> void:
	match object_id:
		"laptop":
			SignalBus.open_laptop_request.emit()
		"notes":
			SignalBus.open_notes_request.emit()
		"calendar":
			SignalBus.open_calendar_request.emit()
		"caller":
			%caller_page.open_dialer()
		_:
			push_warning("物件「%s」没有自带的弹窗" % object_id)


## 今天用第几天的剧本（story_book.plan_for 的参数）。
##
## 平时就是关卡图当前天节点的 plan。测试和调试会直接改 current_day 跳到某一天，
## 那时关卡图还停在原地，就退回按 current_day 取——两者对不上时信 current_day。
func current_plan_day() -> int:
	if level != null and level.doc != null and level.day == current_day:
		return level.plan_day()
	return current_day


## 今天的剧本，没配就是 null（退回纯随机玩法）。
func current_plan() -> day_plan:
	return %story_book.plan_for(current_plan_day())


func _change_state(rs: RoundState.Round_State) -> void:
	RoundState.current_round_state = rs
	_enter_state(rs)


func _enter_state(rs: RoundState.Round_State) -> void:
	match rs:
		RoundState.Round_State.STORY:
			%day_clock.stop()
		RoundState.Round_State.GAME:
			%day_clock.start()
	SignalBus.round_state_change.emit(rs)


## 发信元件：清空昨天的收件箱，按剧本排好人事表、发随机信和剧情信。
##
## **电脑不会隔夜自动锁上**：第 1 天敲完密码就一直登着。
## 想换号（后面几天拿到别人的账户）得自己去选择页 Sign out。
func _send_mails(plan: day_plan) -> void:
	# 隔夜的邮件和指令都不留，每天从干净的收件箱开始。
	%email_reader.clear_inbox()
	%instruction_box.clear_box()

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


## 把当天的信整批重发一次（剧情信照旧，随机信重掷）。顺序和 _send_mails 一致：
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


## 下班元件：停钟、收窗口、判分、记日志、扣命。结果留给结算画面元件显示。
## 当天的 [score] 效果排在它后面——那些规则查的就是这里刚写进去的日志。
func _clock_out() -> void:
	_change_state(RoundState.Round_State.RESULT)
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
	_last_result = result


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
	# [score] 不在这里判了：它们是天内图里排在下班元件后面的效果节点。
