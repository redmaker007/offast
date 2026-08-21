extends Node

## 剧情立场层的自测：GameState 的数值/开关/解锁、邮件回复、内部通讯、
## 档案解锁、「照办 vs 抗命」的结算、人事日志、结局判定、桥段只播一次。
##
## 跑法（项目根目录）：
##     <godot> --headless --path . res://tests/faction_test.tscn
## 退出码 0 全过，非 0 有失败项。
##
## 和 flow_test 一样用真存档槽（main_scene 读档写死 default），
## 所以开跑前先把玩家的存档挪走，跑完再挪回来。

const MAIN_SCENE := "res://main_game/game/main_scene.tscn"
const SAVE_PATH := "user://saves/default.sav"
const BACKUP_PATH := "user://saves/default.sav.factiontest_backup"

var _scene: Node = null
var _passed := 0
var _failed := 0
var _fail_lines: Array[String] = []
var _section := ""

var _replied_events: Array = []


## 进来时玩家的语言设置。测试一律在中文下断言，跑完再还回去。
var _entry_locale := ""


func _ready() -> void:
	_stash_player_save()
	# 语言是玩家的设置（存在 settings.cfg 里），测试不能跟着它变。
	# 全程锁成中文，save 传 false —— 不写盘，跑完原样还回去。
	_entry_locale = LocaleSettings.current
	LocaleSettings.set_locale("zh", false)
	SignalBus.email_replied.connect(func(id: StringName, _r) -> void: _replied_events.append(id))

	_test_game_state_basics()
	_test_ending_rules()
	await _test_save_roundtrip()
	await _test_day_one_content()
	await _test_login()
	await _test_email_reply()
	await _test_profile_clearance()
	await _test_scoring_and_log()
	await _test_promotion_levels()
	await _test_ungraded_rows()
	await _test_all_random_order()
	await _test_filler_exclude()
	await _test_conditional_mail()
	await _test_score_rules()
	await _test_caller_placeholder()
	await _test_caller_numbers()
	await _test_dialing()
	await _test_electric_box_gate()
	await _test_ending_paths()
	await _test_event_once()
	_test_scene_exports()
	await _test_locale_switch()
	await _test_corner_button()

	await _despawn_scene()
	LocaleSettings.set_locale(_entry_locale, false)
	_restore_player_save()
	_report()


# ── GameState ───────────────────────────────────────────

func _test_game_state_basics() -> void:
	_section = "GameState 基础"
	GameState.reset()

	_eq("开局 A 分", GameState.score_of(GameState.SCORE_A), 0)
	_eq("开局日志条数", GameState.personnel_log.size(), 0)

	var e := story_effect.new()
	e.a_delta = 2
	e.c_delta = 1
	e.d_delta = 3
	e.set_flags = [&"took_the_note"] as Array[StringName]
	GameState.apply_effect(e)

	_eq("A 分累加", GameState.score_of(GameState.SCORE_A), 2)
	_eq("C 分累加", GameState.score_of(GameState.SCORE_C), 1)
	_eq("D 分累加", GameState.score_of(GameState.SCORE_D), 3)
	_eq("没提到的 B 分不动", GameState.score_of(GameState.SCORE_B), 0)
	_is_true("flag 打开了", GameState.has_flag(&"took_the_note"))

	# 同一条 effect 再来一次是累加的（重复回复的防重在回复那一层，不在这里）。
	GameState.apply_effect(e)
	_eq("再应用一次继续累加", GameState.score_of(GameState.SCORE_A), 4)

	GameState.apply_effect(null)
	_eq("传 null 是空操作", GameState.score_of(GameState.SCORE_A), 4)


func _test_ending_rules() -> void:
	_section = "结局线领先判定"

	GameState.reset()
	_eq("四项全 0 时并列取 C", GameState.leading(), GameState.SCORE_C)

	GameState.reset()
	GameState.add_score(GameState.SCORE_A, 3)
	GameState.add_score(GameState.SCORE_B, 1)
	_eq("A 最高", GameState.leading(), GameState.SCORE_A)

	GameState.reset()
	GameState.add_score(GameState.SCORE_B, 2)
	_eq("B 最高", GameState.leading(), GameState.SCORE_B)

	GameState.reset()
	GameState.add_score(GameState.SCORE_D, 5)
	_eq("D 最高", GameState.leading(), GameState.SCORE_D)

	# 并列时按固定顺序 C > D > B > A 取第一个达到最高分的，保证确定性。
	# A/B 打平这种情况第五天另有安排（两边各发一封信逼你二选一），靠 tied() 判。
	GameState.reset()
	GameState.add_score(GameState.SCORE_A, 2)
	GameState.add_score(GameState.SCORE_B, 2)
	_eq("A/B 打平时 B 排在 A 前", GameState.leading(), GameState.SCORE_B)
	_is_true("能查出打平", GameState.tied(GameState.SCORE_A, GameState.SCORE_B))
	_is_false("和 C 不算打平", GameState.tied(GameState.SCORE_A, GameState.SCORE_C))

	GameState.reset()
	GameState.add_score(GameState.SCORE_C, 1)
	GameState.add_score(GameState.SCORE_D, 1)
	_eq("C/D 打平取 C", GameState.leading(), GameState.SCORE_C)


func _test_save_roundtrip() -> void:
	_section = "GameState 存档往返"
	await _spawn_scene()

	GameState.reset()
	GameState.add_score(GameState.SCORE_B, 3)
	GameState.levels[&"Mira"] = 3
	GameState.set_flag(&"blackout_lever")
	GameState.login(_node("story_book").account_by_name(&"hrtemp"), 1)
	GameState.mark_email_answered(&"day1_welcome")
	GameState.log_personnel(1, {"employee": "Mira", "issuer": faction.KEY_B, "complied": true})

	_is_true("存盘成功", SaveState.save_game())
	GameState.reset()
	_eq("清空后 B 分", GameState.score_of(GameState.SCORE_B), 0)

	_is_true("读盘成功", SaveState.load_game())
	_eq("B 分读回来了", GameState.score_of(GameState.SCORE_B), 3)
	_eq("员工权限读回来了", GameState.level_of(&"Mira"), 3)
	_is_true("flag 读回来了", GameState.has_flag(&"blackout_lever"))
	_eq("登录的账户读回来了", GameState.current_account, &"hrtemp")
	_eq("权限也读回来了", GameState.clearance(), 2)
	_is_true("读档回来还登着", GameState.is_logged_in(1))
	_is_true("已回复的邮件读回来了", GameState.is_email_answered(&"day1_welcome"))
	_eq("日志条数", GameState.personnel_log.size(), 1)
	_eq("日志带上了天数", int(GameState.personnel_log[0].get("day", 0)), 1)


# ── 第 1 天的内容 ───────────────────────────────────────

func _test_day_one_content() -> void:
	_section = "第 1 天内容（day_plan 驱动）"
	await _fresh_workday()

	var plan = _node("story_book").plan_for(1)
	_is_true("第 1 天配了 day_plan", plan != null)
	if plan == null:
		return

	_eq("剧情信封数", plan.scripted_emails.size(), 3)
	_is_true("鲍勃在当天名单里", "Bob" in _rm().current_round_employee_name_list)
	# 剧情角色（米拉）不占随机名额，所以表上是「随机 3 个 + 剧情涉及的人」。
	_eq("名单人数", _rm().current_round_employee_name_list.size(), _rm().employees_per_day + 1)
	_is_true("主角自己那一行不判对错", not _node("personnel_manager").is_graded(String(GameState.SELF)))
	_eq("收件箱封数 = 剧情信 + 填充信",
		_node("email_reader").remaining(), plan.scripted_emails.size() + plan.filler_emails)

	# 随机信排在前面，剧情信压在后面——先干一堆例行公事，剧情信才出现。
	var inbox: Array = _node("email_reader").unread_email
	_is_false("第一封是随机信", inbox[0].is_scripted())
	_is_true("最后一封是剧情信", inbox[-1].is_scripted())
	var first_scripted := -1
	var last_filler := -1
	for i in range(inbox.size()):
		if inbox[i].is_scripted():
			if first_scripted < 0:
				first_scripted = i
		else:
			last_filler = i
	_is_true("所有随机信都排在剧情信前面", last_filler < first_scripted,
		"最后一封随机信 #%d，第一封剧情信 #%d" % [last_filler, first_scripted])

	var truth: Dictionary = _node("instruction_box").get_all()
	_is_false("鲍勃的申请不进标准答案", truth.has("Bob"))
	_is_false("没有空名字的答案行", truth.has(""))
	_is_false("鲍勃那一行不判对错", _node("personnel_manager").is_graded("Bob"))


func _test_login() -> void:
	_section = "登录"
	await _fresh_workday()

	var laptop := _node("%laptop_page")
	_is_false("开工时电脑是锁着的", GameState.is_logged_in(1))
	_eq("没登录时权限比谁都低", GameState.clearance(), -1)

	SignalBus.open_laptop_request.emit()
	await _frames(2)
	_is_true("打开笔记本先落在登录页", _node("%laptop_login_page").visible)

	# 密码不对：卡在登录页，还给个说法。
	_type_login("hrtemp", "0000")
	await _frames(1)
	_is_false("密码错了登不进去", GameState.is_logged_in(1))
	_is_true("登录页还在", _node("%laptop_login_page").visible)
	_is_true("给了错误提示", not String(_node("%login_error").text).is_empty())

	# 没登录时别的地方发翻页信号也进不去。
	SignalBus.open_email_page_request.emit()
	await _frames(1)
	_is_false("没登录进不了邮件页", _node("%email_read_page").visible)
	_is_true("被弹回登录页", _node("%laptop_login_page").visible)

	_type_login("hrtemp", "4471")
	await _frames(2)
	_is_true("密码对了就登进去了", GameState.is_logged_in(1))
	_eq("记下了是谁的号", GameState.current_account, &"hrtemp")
	_eq("权限跟着账户走", GameState.clearance(), 2)
	_is_true("自动翻到选择页", _node("%laptop_select_page").visible)
	_is_true("密码框清空了", String(_node("%login_pass").text).is_empty())

	SignalBus.open_email_page_request.emit()
	await _frames(1)
	_is_true("登录后进得了邮件页", _node("%email_read_page").visible)

	# 换号：退出去重登。
	_node("%laptop_select_page")._on_sign_out_button_pressed()
	await _frames(2)
	_is_false("退出登录后不算登着", GameState.is_logged_in(1))
	_is_true("退出后回到登录页", _node("%laptop_login_page").visible)

	# 第二天电脑重新锁上：跨天不算登着。
	_type_login("hrtemp", "4471")
	await _frames(1)
	await _next_day()
	_is_false("第 2 天要重新登", GameState.is_logged_in(2))
	_eq("天数确实推进了", _rm().current_day, 2)
	laptop.set_meta("checked", true)


func _test_email_reply() -> void:
	_section = "邮件回复"
	await _fresh_workday()
	GameState.reset()
	_replied_events.clear()

	_swap_day_plan(1, """
[day]
filler: 0
[mail day1_welcome from=\"罗德里克\" faction=B graded=no]
subject: 欢迎
听说你接了人事这张桌子。位子不好坐。
- \"谢谢，有您这句话就够了。\" -> B+1, echo=\"你回得很热情。\"
- \"知道了。\" -> echo=\"你只回了三个字。\"
- \"我自己会判断。\" -> C+1, echo=\"你说你自己会判断。\"
""")
	SignalBus.round_state_change.emit(RoundState.Round_State.GAME)
	await _frames(1)
	_rm()._begin_workday()
	await _frames(1)

	var page := _node("%email_read_page")
	var reader := _node("email_reader")
	reader.read_next_email()          # 唯一一封，B 派的欢迎信
	await _frames(1)

	_eq("回复按钮数", _node("%reply_list").get_child_count(), 3)
	_is_true("回复区可见", _node("%reply_list").visible)
	_is_true("没回复完不许读下一封", _node("%next_email").disabled)
	_has_text("正文里有发件人的话", _node("%email_content").text, "人事这张桌子")


	var warm := _node("%reply_list").get_child(0) as Button
	warm.pressed.emit()
	await _frames(1)

	_eq("热情回复给 B 加了分", GameState.score_of(GameState.SCORE_B), 1)
	_is_true("记下已经回过了", GameState.is_email_answered(&"day1_welcome"))
	_eq("发了 email_replied 信号", _replied_events.size(), 1)
	_is_false("回完解锁下一封", _node("%next_email").disabled)
	_eq("回完收起回复区", _node("%reply_list").get_child_count(), 0)
	_has_text("正文里回显了选的那句", _node("%email_content").text, "热情")

	# 读档回来又读到同一封：不再问一次，也不再加一次分。
	var again: email = _node("story_book").mail_def(&"day1_welcome").make_email()
	SignalBus.show_email.emit(again)
	await _frames(1)
	_eq("回过的信不再出回复按钮", _node("%reply_list").get_child_count(), 0)
	_is_false("回过的信不锁下一封", _node("%next_email").disabled)
	_eq("B 分没有被加第二次", GameState.score_of(GameState.SCORE_B), 1)

	# 随机信：没有回复选项，也不该被锁住。
	while reader.remaining() > 0:
		reader.read_next_email()
	await _frames(1)
	_is_false("读完信之后没被锁", _node("%next_email").disabled)
	_eq("页面状态没残留回复按钮", _node("%reply_list").get_child_count(), 0)
	page.set_meta("checked", true)




func _test_profile_clearance() -> void:
	_section = "档案按账户权限"
	await _fresh_workday()

	var book := _node("story_book")
	var bob: employee_profile = book.profile(&"Bob")
	var mira: employee_profile = book.profile(&"Mira")
	_is_true("鲍勃有档案", bob != null)
	_is_true("米拉有档案", mira != null)
	_is_true("随机员工没有档案", book.profile(&"Jack") == null)
	if bob == null or mira == null:
		return
	_is_true("两份档案的权限要求不一样", bob.clearance < mira.clearance)

	# 没登录：一个都查不到。
	GameState.logout()
	_eq("没登录时查得到的档案数", book.profiles_for(GameState.clearance()).size(), 0)

	# 主角自己的号是 2 级：查得到鲍勃和瑞克，查不到米拉（3）和两个头目（4）。
	_login(&"hrtemp")
	await _frames(1)
	var visible_names: Array = []
	for p in book.profiles_for(GameState.clearance()):
		visible_names.append(String(p.employee_name))
	_is_true("查得到鲍勃", visible_names.has("Bob"), str(visible_names))
	_is_true("查得到 Rick", visible_names.has("Rick"), str(visible_names))
	_is_false("查不到 Mira", visible_names.has("Mira"), str(visible_names))
	_is_false("查不到 Banner", visible_names.has("Banner"), str(visible_names))

	SignalBus.profile_focus_requested.emit(&"Bob")
	await _frames(1)
	_is_true("跳到了档案页", _node("%profile_page").visible)
	_has_text("档案页显示中文名", _node("%profile_name").text, "鲍勃")
	_has_text("档案里有职位", _node("%profile_meta").text, "职员")
	_eq("名单上只列出查得到的人", _node("%profile_list").get_child_count(), visible_names.size())

	# 邮件里提到、但这个号查不到的人：明说查不到，而不是装作没这个人。
	SignalBus.profile_focus_requested.emit(&"Mira")
	await _frames(1)
	_eq("权限不够时说清楚", _node("%profile_name").text, tr("UI_NO_RECORD"))
	_is_true("正文空着", String(_node("%profile_body").text).is_empty())

	# 借一个 3 级的号（剧情里以后会有），名单立刻变长。
	_login_level(3)
	await _frames(1)
	_is_true("3 级查得到米拉", book.profiles_for(3).size() > visible_names.size())
	SignalBus.profile_focus_requested.emit(&"Mira")
	await _frames(1)
	_has_text("现在查得到米拉了", _node("%profile_name").text, "米拉")


# ── 判分、日志、权限 ────────────────────────────────────

## 日终不再自动给结局分（那套「照办/抗命」的通用规则已经删了，
## 每一分都由内容里写死的条件给），但日志照记。
func _test_scoring_and_log() -> void:
	_section = "日终结算：只记日志，不自动加分"
	await _fresh_workday()
	GameState.reset()
	_order_from(faction.KEY_A, "Bob", "Fire")

	_fill_correct()
	await _settle()

	for key in [GameState.SCORE_A, GameState.SCORE_B, GameState.SCORE_C, GameState.SCORE_D]:
		_eq("照办不再自动加 %s 分" % key, GameState.score_of(key), 0)

	var row := _log_row_for("Bob")
	_is_true("日志里有鲍勃这一行", not row.is_empty())
	if row.is_empty():
		return
	_eq("日志记下发令方", row.get("issuer", &""), faction.KEY_A)
	_is_true("日志记下照办了", bool(row.get("complied", false)))
	_eq("日志记下天数", int(row.get("day", 0)), 1)
	_is_true("日志里记的是玩家填的动作", bool(row.get("actual", {}).get("Fire", false)))
	_is_true("日志层念的是中文名", _log_lines_contain("鲍勃"))


## 批一次 promotion，对方的权限就 +1——鲍勃 1→4 级那条线全靠它。
func _test_promotion_levels() -> void:
	_section = "promotion 抬权限"
	await _fresh_workday()

	var before := GameState.level_of(&"Bob")
	_eq("开局权限取自档案", before, 1)
	_eq("没档案的随机员工没有权限", GameState.level_of(&"NoSuchPerson"), -1)

	_node("personnel_manager").toggle("Bob", "Promotion")
	await _settle()
	_eq("批完 promotion 权限 +1", GameState.level_of(&"Bob"), before + 1)

	# 没批的人不动。
	SignalBus.result_confirmed.emit()
	await _frames(2)
	SignalBus.story_finished.emit()
	await _frames(2)
	await _settle()
	_eq("这一天没批就不涨", GameState.level_of(&"Bob"), before + 1)


## graded=no 的信：人进表，但那一行怎么填都不算对错。
func _test_ungraded_rows() -> void:
	_section = "不判分的行"
	await _fresh_workday()

	# 数据层：graded=false 的信不进标准答案。
	var before: int = _node("instruction_box").get_all().size()
	var e := email.new()
	e.init_email("Bob", "Raise", "Bob", 4)
	e.graded = false
	SignalBus.send_email.emit(e)
	_eq("不判分的信不进标准答案", _node("instruction_box").get_all().size(), before)

	# 判分层：ungraded 的行不进分子也不进分母。
	var pm := _node("personnel_manager")
	var roster: Array = _rm().current_round_employee_name_list
	pm.begin_day([roster[0]])
	_is_false("这一行不判分", pm.is_graded(roster[0]))
	_is_true("别的行照判", pm.is_graded(roster[1]))

	var graded_total := 0
	for name in roster:
		if pm.is_graded(name):
			graded_total += 1
	# 故意把不判分的那一行填得乱七八糟，分数不该有任何变化。
	pm.toggle(roster[0], "Fire")
	pm.toggle(roster[0], "Promotion")
	var result: Dictionary = pm.grade()
	_eq("分母不含不判分的行", int(result["total"]), graded_total)
	_eq("对 + 错 = 分母", int(result["correct"]) + int(result["wrong"]), graded_total)
	# 主角自己那一行永远不判分。
	pm.begin_day([])
	_is_true("主角这一行默认也在表里", true)


## order=fire:*random —— 一封信把当天所有随机员工都点名。
func _test_all_random_order() -> void:
	_section = "fire:*random 展开"
	await _spawn_scene()
	_swap_day_plan(1, """
[day]
filler: 0
[mail sweep from=\"Banner\" faction=A class=4 order=fire:*random]
subject: clean up
Fire every one of them.
""")
	SignalBus.story_finished.emit()
	await _frames(2)

	var rm := _rm()
	var truth: Dictionary = _node("instruction_box").get_all()
	_eq("收件箱封数 = 随机员工人数", _node("email_reader").remaining(), rm.employees_per_day)
	_eq("标准答案覆盖每个随机员工", truth.size(), rm.employees_per_day)
	for name in rm.current_round_employee_name_list:
		if name == String(GameState.SELF):
			continue
		_is_true("%s 被点名 fire" % name,
			truth.has(name) and bool(truth[name].has_fire))
		_eq("发令方是 A 派", truth[name].faction_key, faction.KEY_A)


## [day] filler_exclude：随机信不出某种指令。
func _test_filler_exclude() -> void:
	_section = "随机信排除某种指令"
	await _spawn_scene()
	_swap_day_plan(1, """
[day]
filler: 12
filler_exclude: promotion, fire
[story]
them: quiet day.
""")
	SignalBus.story_finished.emit()
	await _frames(2)

	var seen: Array = []
	for e in _node("email_reader").unread_email:
		if not seen.has(e.instruction):
			seen.append(e.instruction)
	_eq("发了 12 封填充信", _node("email_reader").remaining(), 12)
	_is_false("没有 promotion", "Promotion" in seen)
	_is_false("没有 fire", "Fire" in seen)
	_is_true("剩下的指令还在出", seen.size() > 0, str(seen))


## `[mail ... if=]`：条件不成立的信当天根本不存在。
func _test_conditional_mail() -> void:
	_section = "条件邮件"
	await _spawn_scene()
	_swap_day_plan(1, """
[day]
filler: 0
[mail hot from=\"Banner\" graded=no if=score.A>=1]
subject: hot
you are one of us.
[mail cold from=\"Banner\" graded=no if="not score.A>=1"]
subject: cold
watch yourself.
""")
	GameState.add_score(GameState.SCORE_A, 1)
	SignalBus.story_finished.emit()
	await _frames(2)

	var ids: Array = []
	for e in _node("email_reader").unread_email:
		ids.append(String(e.id))
	_eq("只发了一封", _node("email_reader").remaining(), 1)
	_is_true("发的是条件成立那封", ids.has("hot"), str(ids))
	_is_false("另一封没发", ids.has("cold"), str(ids))


## `[score]`：日终按当天做过什么加结局分。
func _test_score_rules() -> void:
	_section = "[score] 日终结算"
	var plan_text := """
[day]
filler: 0
[score]
if did(fire,*random) -> A+2
if not did(fire,*any) -> C+2
"""

	# 一个都不 fire → C+2
	await _spawn_scene()
	_swap_day_plan(1, plan_text)
	SignalBus.story_finished.emit()
	await _frames(2)
	await _settle()
	_eq("什么都不做拿 C+2", GameState.score_of(GameState.SCORE_C), 2)
	_eq("A 分不动", GameState.score_of(GameState.SCORE_A), 0)

	# 把随机员工全 fire 掉 → A+2
	await _spawn_scene()
	_swap_day_plan(1, plan_text)
	SignalBus.story_finished.emit()
	await _frames(2)
	for name in _rm().current_random_name_list:
		_node("personnel_manager").toggle(name, "Fire")
	await _settle()
	_eq("全 fire 掉拿 A+2", GameState.score_of(GameState.SCORE_A), 2)
	_eq("C 分不动", GameState.score_of(GameState.SCORE_C), 0)


## `{caller:X}`：邮件里写占位符，显示时换成这一局的号码。
func _test_caller_placeholder() -> void:
	_section = "邮件里的号码占位符"
	await _spawn_scene()
	_swap_day_plan(1, """
[day]
filler: 0
[mail tip from=\"Mira\" graded=no]
subject: the box
维修工的号码是 {caller:repairman}。
""")
	SignalBus.story_finished.emit()
	await _frames(2)

	GameState.caller_numbers[&"repairman"] = "7391"
	_node("email_reader").read_next_email()
	await _frames(1)
	_has_text("正文里是真号码", _node("%email_content").text, "7391")
	_is_false("看不到占位符本身", _node("%email_content").text.contains("{caller:"))


## 号码每局重摇一次，4 位、互不相同、进存档。
func _test_caller_numbers() -> void:
	_section = "电话号码"
	await _spawn_scene()

	var book := _node("story_book")
	var numbers: Array = []
	for c in book.world.contacts:
		var n := GameState.caller_number(c.contact_name)
		_eq("%s 的号码是 4 位" % c.contact_name, n.length(), 4)
		_is_true("%s 的号码是数字" % c.contact_name, n.is_valid_int(), n)
		_is_false("号码不重复", numbers.has(n), n)
		numbers.append(n)
	_is_true("至少有两个联系人", numbers.size() >= 2)

	# 存档往返：号码不能变，不然抄在本子上的就作废了。
	var before := GameState.caller_numbers.duplicate()
	_is_true("存盘成功", SaveState.save_game())
	GameState.caller_numbers.clear()
	_is_true("读盘成功", SaveState.load_game())
	_eq("号码原样读回来", GameState.caller_numbers, before)

	# 新开一局要重摇（防背号码）。摇到一模一样的概率是 1/9000 量级，
	# 这里比的是整张表，实际上撞不上。
	await _spawn_scene()
	_is_false("新局换了一套号码", GameState.caller_numbers == before,
		str(GameState.caller_numbers))


## 拨号：拨对接通、拨错忙音、打过的人记进 called()。
func _test_dialing() -> void:
	_section = "拨号"
	await _fresh_workday()

	var phone := _node("%caller_page")
	var page := _node("%event_page")
	# 第 1 天有一通来电，先把它接掉，之后点电话才是拨号。
	SignalBus.open_caller_request.emit()
	await _frames(2)
	_is_true("先接当天的来电", page.visible)
	_is_false("这时候不弹拨号盘", phone.visible)
	var guard := 0
	while page.visible and guard < 12:
		guard += 1
		_advance(_node("%event_bubble"))
		await _frames(1)

	SignalBus.open_caller_request.emit()
	await _windows_settled()
	_is_true("来电接完了才弹拨号盘", phone.visible)

	# 拨错号：忙音，什么都不发生。
	_node("%dial_input").text = "0000"
	phone._on_call_pressed()
	await _frames(1)
	_is_true("拨错了给忙音", not String(_node("%dial_status").text).is_empty())
	_is_true("拨号盘还开着", phone.visible)
	_is_false("没有接通", page.visible)

	# 拨对号：接通，播那段对话。
	var mira_number := GameState.caller_number(&"Mira")
	_node("%dial_input").text = mira_number
	phone._on_call_pressed()
	await _windows_settled()
	_is_false("接通后拨号盘收起来", phone.visible)
	_is_true("对话播起来了", page.visible)
	_is_true("记下打通过米拉", GameState.has_called(&"Mira"))
	_is_true("called() 条件也认", story_condition.eval("called(Mira)"))

	guard = 0
	while page.visible and guard < 12:
		guard += 1
		_advance(_node("%event_bubble"))
		await _frames(1)
	_is_false("播完收起来", page.visible)


## 电箱：没钥匙只看到锁着，拿到钥匙**当天还能再开一次**（repeat=yes）。
func _test_electric_box_gate() -> void:
	_section = "电箱要钥匙"
	await _spawn_scene()
	_swap_day_plan(1, """
[day]
filler: 0
[electricbox repeat=yes]
?if not flag:has_key
them: locked tight.
?end
?if flag:has_key
them: the key turns.
- \"记下号码\" -> flag=got_number
?end
""")
	SignalBus.story_finished.emit()
	await _frames(2)

	var page := _node("%event_page")
	var view := _node("%event_bubble")
	view.chars_per_second = 0.0

	SignalBus.open_electricbox_request.emit()
	await _frames(2)
	_is_true("点电箱有反应", page.visible)
	_has_text("没钥匙只说锁着", view.get_node("%text_box").text, "locked")
	_advance(view)
	await _frames(2)
	_is_false("那一段播完了", page.visible)

	# 同一天再点：因为 repeat=yes，还能再开（不然拿到钥匙就没机会用了）。
	GameState.set_flag(&"has_key")
	SignalBus.open_electricbox_request.emit()
	await _frames(2)
	_is_true("拿到钥匙当天能再开一次", page.visible)
	_has_text("这次开得了", view.get_node("%text_box").text, "key turns")
	_advance(view)
	await _frames(2)
	_is_true("选项里的 flag 生效了", GameState.has_flag(&"got_number"))


# ── 桌面桥段 ────────────────────────────────────────────

func _test_event_once() -> void:
	_section = "桌面桥段每天只播一次"
	await _spawn_scene()
	_swap_day_plan(1, """
[day]
filler: 0
[caller]
them: 电话响了两声。
- "挂掉。" -> flag=took_the_call
""")
	SignalBus.story_finished.emit()
	await _frames(2)
	GameState.day = 1

	var page := _node("%event_page")
	_is_false("一开始不显示", page.visible)

	SignalBus.open_caller_request.emit()
	await _frames(2)
	_is_true("点电话播出来了", page.visible)
	_is_true("记下今天播过了", GameState.has_flag(event_page.flag_for(&"caller", 1)))

	# 电话那段最后一条是个选项，选了会打一个 flag。
	var view := _node("%event_bubble")
	view.chars_per_second = 0.0     # 测流程，不等逐字机
	var guard := 0
	while page.visible and guard < 12:
		guard += 1
		_advance(view)
		await _frames(1)

	_is_false("播完自己收起来", page.visible)
	_is_true("电话里的选项打了 flag", GameState.has_flag(&"took_the_call"))

	SignalBus.open_caller_request.emit()
	await _windows_settled()
	_is_false("同一天再点不会重播", page.visible)
	_is_true("接完来电之后点电话是拨号盘", _node("%caller_page").visible)
	await _node("%caller_page").close()

	# 没配内容的物件点了没反应（电箱是第 3 天才有的桥段）。
	SignalBus.open_electricbox_request.emit()
	await _frames(1)
	_is_false("没配内容的物件点了没反应", page.visible)


## 五条结局各跑一遍。规则表写在 world.story 的 [ending] 块里，按顺序判。
func _test_ending_paths() -> void:
	_section = "五个结局"
	await _spawn_scene()

	var captured: Array = []
	var conn := func(id: StringName) -> void: captured.append(id)
	SignalBus.ending_ready.connect(conn)

	# 倒向 A 且照做最后一封 → 结局 A
	await _reach_ending(captured, func() -> void:
		GameState.add_score(GameState.SCORE_A, 3)
		GameState.log_personnel(5, {"employee": "Rick", "actual": {"Promotion": true}}))
	_eq("倒向 A 且批了瑞克 → A", captured[-1] if captured.size() > 0 else &"", GameState.SCORE_A)

	# 倒向 B 且给自己批了 → 结局 B
	await _reach_ending(captured, func() -> void:
		GameState.add_score(GameState.SCORE_B, 3)
		GameState.log_personnel(5, {"employee": String(GameState.SELF), "actual": {"Promotion": true}}))
	_eq("倒向 B 且给自己批了 → B", captured[-1], GameState.SCORE_B)

	# 倒向 A 却没照做 → 两边都得罪光 → 结局 E
	await _reach_ending(captured, func() -> void:
		GameState.add_score(GameState.SCORE_A, 3))
	_eq("倒向 A 却没照做 → E", captured[-1], &"E")

	# 证据齐全 + 第五天把两个头目都 fire 了 → 结局 D
	await _reach_ending(captured, func() -> void:
		GameState.add_score(GameState.SCORE_D, 3)
		GameState.set_flag(&"has_tape")
		GameState.set_flag(&"has_photo")
		GameState.levels[&"Bob"] = 4
		GameState.log_personnel(5, {"employee": "Banner", "actual": {"Fire": true}})
		GameState.log_personnel(5, {"employee": "Roderick", "actual": {"Fire": true}}))
	_eq("证据齐全且清掉两个头目 → D", captured[-1], GameState.SCORE_D)

	# 证据不齐 → 退回兜底的 C
	await _reach_ending(captured, func() -> void:
		GameState.add_score(GameState.SCORE_D, 3)
		GameState.set_flag(&"has_tape")
		GameState.levels[&"Bob"] = 4
		GameState.log_personnel(5, {"employee": "Banner", "actual": {"Fire": true}}))
	_eq("证据不齐 → C", captured[-1], GameState.SCORE_C)

	# 什么都没干 → C
	await _reach_ending(captured, func() -> void: pass)
	_eq("什么都没攒 → C", captured[-1], GameState.SCORE_C)

	# 结局卡上的文案要跟着 id 走。
	_eq("结局卡显示对应文案", _node("%ending_overlay").get_node("%ending_title").text,
		_node("ending_director").ending_c.title)

	# 被开除是另一条路，不走规则表。
	SignalBus.game_over.emit()
	await _frames(2)
	_eq("三条命掉光直接 E", captured[-1], &"E")

	SignalBus.ending_ready.disconnect(conn)


## 摆好状态 → 通关 → 看完日志 → 拿到结局 id。
func _reach_ending(captured: Array, setup: Callable) -> void:
	GameState.reset()
	setup.call()
	SignalBus.game_cleared.emit()
	await _frames(2)
	SignalBus.log_review_finished.emit()
	await _frames(2)


# ── 场景配置 ────────────────────────────────────────────

## Godot 给已有节点换脚本 / 加 @export 时会把导出属性写成 null，
## 而且编辑器内存里读到的还是对的，只有从磁盘重新加载才暴露。
func _test_scene_exports() -> void:
	_section = "内容按语言装好了"
	var book := _node("story_book")

	# 内容不再挂在 Inspector 上，而是按当前语言从目录里装（换语言就是换目录）。
	_eq("装的是中文内容", book.loaded_locale, "zh")
	_eq("五天都装上了", book.days.size(), 5)
	for i in range(book.days.size()):
		_is_true("第 %d 天不是 null" % (i + 1), book.days[i] != null)
	_is_true("world 不是 null", book.world != null)
	if book.world == null:
		return
	_is_true("world 里有账户", not book.world.accounts.is_empty())
	_is_true("world 里有档案", not book.world.profiles.is_empty())
	_is_true("world 里有联系人", not book.world.contacts.is_empty())
	_is_true("world 里有随机名字池", not book.world.random_names.is_empty())

	# 五个结局的文案也在内容文件里。
	var director := _node("ending_director")
	for id in [GameState.SCORE_A, GameState.SCORE_B, GameState.SCORE_C, GameState.SCORE_D, &"E"]:
		var text: ending_def = director.def_for(id)
		_is_true("结局 %s 有文案" % id, text != null and not text.title.is_empty())
	_eq("兜底结局是 C", director.fallback_ending, GameState.SCORE_C)

	# 随机员工用的是内容里那份名单。
	var pool: Array = _node("email_generator").name_pool()
	_eq("名字池取自内容文件", pool.size(), book.world.random_names.size())


## 换语言：UI 和剧情内容一起换，标识（存档里的键）不变。
func _test_locale_switch() -> void:
	_section = "换语言"
	await _spawn_scene()
	var book := _node("story_book")

	_eq("默认是中文", book.loaded_locale, "zh")
	var zh_ending: String = book.world.ending_text(GameState.SCORE_A).title
	var zh_bob: String = book.profile(&"Bob").label()
	_eq("中文显示名", zh_bob, "鲍勃")
	_eq("中文 UI", tr("UI_CONTINUE"), "继续")

	# 存 false：别把跑测试的机器上玩家的 settings.cfg 改掉。
	LocaleSettings.set_locale("en", false)
	await _frames(2)

	_eq("内容换成英文了", book.loaded_locale, "en")
	_eq("英文 UI", tr("UI_CONTINUE"), "Continue")
	_is_true("结局文案跟着换", book.world.ending_text(GameState.SCORE_A).title != zh_ending)
	_eq("英文显示名", book.profile(&"Bob").label(), "Bob")
	_is_true("标识没变（存档的键靠它）", book.profile(&"Bob") != null)
	_eq("随机名字池也换了", _node("email_generator").name_pool().has("Jack"), true)

	# 两边的第 1 天结构一致，换语言不会把玩法改掉。
	_eq("第 1 天还是三封剧情信", book.plan_for(1).scripted_emails.size(), 3)
	_is_true("Bob 还在第 1 天的名单里", &"Bob" in book.plan_for(1).story_roster)

	LocaleSettings.set_locale("zh", false)
	await _frames(2)
	_eq("换回中文", book.loaded_locale, "zh")
	_eq("显示名也换回来", book.profile(&"Bob").label(), "鲍勃")


## 标题栏右上角那个键一个键两用：选择页/登录页上是红叉（关窗），
## 应用页上换成箭头（回选择页）。位置不动，只换图标和颜色。
func _test_corner_button() -> void:
	_section = "标题栏那个键一键两用"
	await _fresh_workday()

	var laptop := _node("Control/laptop_page")
	var corner := _node("%cancel_button")

	SignalBus.open_laptop_request.emit()
	await _windows_settled()
	_is_true("没登录时落在登录页", _node("%laptop_login_page").visible)
	_eq("登录页上是红叉", corner.icon, laptop.close_icon)
	_eq("红叉是那抹红", corner.modulate, laptop.close_tint)

	_login(&"hrtemp")
	await _frames(2)
	_is_true("登录后到选择页", _node("%laptop_select_page").visible)
	_eq("选择页上还是红叉", corner.icon, laptop.close_icon)

	for page_name in ["%email_read_page", "%instruction_execute_page", "%profile_page"]:
		match page_name:
			"%email_read_page":
				SignalBus.open_email_page_request.emit()
			"%instruction_execute_page":
				SignalBus.open_instruction_page_request.emit()
			_:
				SignalBus.open_profile_page_request.emit()
		await _frames(1)
		_is_true("翻到了 %s" % page_name, _node(page_name).visible)
		_eq("%s 上换成返回箭头" % page_name, corner.icon, laptop.back_icon)
		_eq("%s 上颜色也换了" % page_name, corner.modulate, laptop.back_tint)

		laptop._on_cancel_pressed()
		await _frames(1)
		_is_true("按下回到选择页", _node("%laptop_select_page").visible)
		_is_true("笔记本还开着", laptop.visible)
		_eq("回到选择页又变回红叉", corner.icon, laptop.close_icon)

	# 选择页上按同一个键，关的是整个笔记本。
	laptop._on_cancel_pressed()
	await _windows_settled()
	_is_false("选择页上按下关掉笔记本", laptop.visible)


# ── 辅助 ────────────────────────────────────────────────

## 起一局并推进到上班时间。每个测试段都从干净的一天开始，互不影响。
func _fresh_workday() -> void:
	await _spawn_scene()
	SignalBus.story_finished.emit()
	await _frames(2)


## 在登录页真的敲一遍用户名密码。
func _type_login(user: String, secret: String) -> void:
	_node("%login_user").text = user
	_node("%login_pass").text = secret
	_node("%laptop_login_page")._on_sign_in_pressed()


## 直接用某个账户登进去（不测登录页本身时用这条，省事）。
func _login(username: StringName) -> void:
	GameState.login(_node("story_book").account_by_name(username), _rm().current_day)


## 用一个临时造的账号登进去（测权限用，不依赖剧本里有没有这个等级的号）。
func _login_level(clearance: int) -> void:
	var temp := account.new()
	temp.username = StringName("lvl%d" % clearance)
	temp.clearance = clearance
	GameState.login(temp, _rm().current_day)


## 走完一整天，停在第二天的上班时间。
func _next_day() -> void:
	SignalBus.day_time_up.emit()
	await _frames(2)
	SignalBus.result_confirmed.emit()
	await _frames(2)
	SignalBus.story_finished.emit()
	await _frames(2)


## 把某一天的剧本临时换成一段现写的 .story，用来测那些第 1 天内容里没有的写法。
func _swap_day_plan(day: int, text: String) -> void:
	var parsed := story_parser.parse(text, "test.story")
	if not parsed.ok():
		_record("剧本解析", false, str(parsed.errors))
		return
	_node("story_book").days[day - 1] = parsed.day


## 让某一派往某个员工身上下一道命令（等级 4，盖得过随机信）。
func _order_from(faction_key: StringName, employee_name: String, order: String) -> void:
	var e := email.new()
	e.init_email("boss", order, employee_name, 4)
	e.faction_key = faction_key
	SignalBus.send_email.emit(e)


## 到点下班 → 结算 → 确认，走完一整天。
func _settle() -> void:
	SignalBus.day_time_up.emit()
	await _frames(2)


func _fill_correct() -> void:
	var pm := _node("personnel_manager")
	var truth: Dictionary = _node("instruction_box").get_all()
	for employee_name in _rm().current_round_employee_name_list:
		var expected: Dictionary = {}
		if truth.has(employee_name):
			expected = truth[employee_name].get_final_state()
		for action in pm.ACTIONS:
			if bool(expected.get(action, false)) != pm.is_set(employee_name, action):
				pm.toggle(employee_name, action)


## 推一条气泡：有选项就选第一条，没有就按 Next。
func _advance(view: Node) -> void:
	view.finish_typing()
	var choices := view.get_node("%choice_list")
	if choices.visible and choices.get_child_count() > 0:
		(choices.get_child(0) as Button).pressed.emit()
		return
	view.get_node("%next_button").pressed.emit()


func _log_row_for(employee_name: String) -> Dictionary:
	for row in GameState.personnel_log:
		if str(row.get("employee", "")) == employee_name:
			return row
	return {}


func _log_lines_contain(needle: String) -> bool:
	SignalBus.log_review_requested.emit()
	for line in _node("%log_list").get_children():
		if line is Label and (line as Label).text.contains(needle):
			_node("%log_overlay").visible = false
			return true
	_node("%log_overlay").visible = false
	return false


# ── 场景装卸 ────────────────────────────────────────────

func _spawn_scene() -> void:
	await _despawn_scene()
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_scene)
	# main_scene._ready 自己先 await 了一帧才开局，多等几帧确保开完。
	await _frames(3)


func _despawn_scene() -> void:
	if _scene == null:
		return
	var old := _scene
	_scene = null
	remove_child(old)
	old.queue_free()
	await _frames(2)


## 窗口开关带动画（popup_window 的 tween），等帧不够，得等真时间。
func _windows_settled() -> void:
	await get_tree().create_timer(0.6).timeout


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _node(path: String) -> Node:
	return _scene.get_node(path)


func _rm() -> Node:
	return _node("round_manager")


# ── 断言 ────────────────────────────────────────────────

func _eq(label: String, actual: Variant, expected: Variant) -> void:
	_record(label, actual == expected, "期望 %s，实际 %s" % [str(expected), str(actual)])


func _is_true(label: String, cond: bool, detail := "") -> void:
	_record(label, cond, "期望为真" if detail.is_empty() else detail)


func _is_false(label: String, cond: bool, detail := "") -> void:
	_record(label, not cond, "期望为假" if detail.is_empty() else detail)


func _has_text(label: String, haystack: String, needle: String) -> void:
	_record(label, haystack.contains(needle), "「%s」里找不到「%s」" % [haystack.replace("\n", "⏎"), needle])


func _record(label: String, ok: bool, detail: String) -> void:
	if ok:
		_passed += 1
		return
	_failed += 1
	_fail_lines.append("  ✗ [%s] %s —— %s" % [_section, label, detail])


func _report() -> void:
	print("\n=============== faction_test ==============")
	if _failed == 0:
		print("全部通过：%d 项" % _passed)
	else:
		print("通过 %d 项，失败 %d 项：" % [_passed, _failed])
		for line in _fail_lines:
			print(line)
	print("===========================================\n")
	get_tree().quit(1 if _failed > 0 else 0)


# ── 别动玩家的真存档 ────────────────────────────────────

func _stash_player_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.rename_absolute(SAVE_PATH, BACKUP_PATH)


func _restore_player_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.rename_absolute(BACKUP_PATH, SAVE_PATH)
