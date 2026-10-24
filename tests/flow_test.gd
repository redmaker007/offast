extends Node

## 三段式玩法的流程自测。不点 UI，直接驱动信号和数据层，
## 覆盖 STORY→GAME→RESULT→次日、判分扣命、人事表动态行、存档往返、结局两条分支。
##
## 跑法（项目根目录）：
##     <godot> --headless --path . res://tests/flow_test.tscn
## 退出码 0 全过，非 0 有失败项。
##
## 存档用的是真存档槽（main_scene 读档写死了 default 槽），所以开跑前先把玩家的
## default.sav 挪走，跑完再挪回来——测试不能吃掉别人的进度。

const MAIN_SCENE := "res://main_game/game/main_scene.tscn"
const MENU_SCENE := "res://main_game/menu/menu_scene.tscn"
const SAVE_PATH := "user://saves/default.sav"
const BACKUP_PATH := "user://saves/default.sav.flowtest_backup"

var _scene: Node = null
var _passed := 0
var _failed := 0
var _fail_lines: Array[String] = []
var _section := ""

## 各测试段自己挂的信号计数器。
var _life_lost_events: Array = []
var _game_over_count := 0
var _game_cleared_count := 0


func _ready() -> void:
	_stash_player_save()
	SignalBus.life_lost.connect(func(remaining: int) -> void: _life_lost_events.append(remaining))
	SignalBus.game_over.connect(func() -> void: _game_over_count += 1)
	SignalBus.game_cleared.connect(func() -> void: _game_cleared_count += 1)

	await _test_story_opening()
	await _test_begin_workday()
	await _test_personnel_rows()
	await _test_leave_blocked()
	await _test_settle_perfect_day()
	await _test_settle_bad_day_costs_life()
	await _test_day_time_up()
	await _test_save_roundtrip()
	await _test_notes_pad()
	await _test_promotion_quota()
	await _test_clear_run()
	await _test_fired_run()
	await _test_ingame_settings()
	await _test_menu_roundtrip()

	await _despawn_scene()
	SceneTransition.clear_retained()
	_restore_player_save()
	_report()


# ── 各测试段 ────────────────────────────────────────────

## 开局停在 STORY：剧情层开着，桌面锁死，时钟不走，还没发邮件。
func _test_story_opening() -> void:
	_section = "STORY 开局"
	await _spawn_scene(false)

	_eq("回合状态", RoundState.current_round_state, RoundState.Round_State.STORY)
	_eq("天数", _rm().current_day, 1)
	_eq("命数", _rm().lives, _rm().max_lives)
	_is_true("剧情层可见", _node("story_page").visible)
	_is_false("桌面可交互", RoundState.is_interactive())
	_is_false("时钟在走", _node("day_clock").is_processing())
	_eq("收件箱封数", _node("email_reader").remaining(), 0)
	_eq("标准答案条数", _node("instruction_box").get_all().size(), 0)


## 剧情播完进 GAME：清空隔夜数据、点名、发邮件、开钟。
func _test_begin_workday() -> void:
	_section = "STORY → GAME（_begin_workday）"
	await _advance_to_game()

	var rm := _rm()
	_eq("回合状态", RoundState.current_round_state, RoundState.Round_State.GAME)
	_is_true("桌面可交互", RoundState.is_interactive())
	_is_false("剧情层可见", _node("story_page").visible)

	# 剧情角色不占随机名额：表 = 今天真收到指令的随机员工 + 当天剧情涉及的人。
	# 随机员工最多抽 employees_per_day 个，谁都没提到的那些不上表（信少于人的日子会剩人）。
	_is_true("随机员工不超过名额", rm.current_random_name_list.size() <= rm.employees_per_day)
	_eq("点名人数", rm.current_round_employee_name_list.size(),
		rm.current_random_name_list.size() + _story_roster_size())
	var box: Dictionary = _node("instruction_box").get_all()
	for name in rm.current_random_name_list:
		_is_true("表上的随机员工 %s 今天真收到了指令" % name, box.has(String(name)))
	_eq("名单去重后人数", _unique(rm.current_round_employee_name_list).size(),
		rm.current_round_employee_name_list.size())
	_eq("收件箱封数", _node("email_reader").remaining(), _expected_mail_count())

	var truth: Dictionary = _node("instruction_box").get_all()
	_is_true("标准答案非空", truth.size() > 0)
	_is_true("标准答案只涉及当天名单", _keys_subset(truth, rm.current_round_employee_name_list),
		"答案里的人：%s；名单：%s" % [truth.keys(), rm.current_round_employee_name_list])

	# 收到的邮件也必须全部打在名单里的人身上，否则玩家没有可填的行。
	var off_roster := 0
	for e in _node("email_reader").unread_email:
		# 不带人事指令的剧情信（欢迎信、打探信）没有目标，不需要表上有行。
		if str(e.target_employee_name).is_empty():
			continue
		if not (e.target_employee_name in rm.current_round_employee_name_list):
			off_roster += 1
	_eq("名单外的邮件封数", off_roster, 0)

	# 当天配了剧情内容的话，剧情角色必须在名单里，否则收到命令也没处填。
	var plan = _node("story_book").plan_for(rm.current_day)
	if plan != null:
		for story_name in plan.story_roster:
			_is_true("剧情角色 %s 在名单里" % story_name,
				String(story_name) in rm.current_round_employee_name_list)

	var clock := _node("day_clock")
	_is_true("时钟在走", clock.is_processing())
	_is_true("时钟从头开始", clock.elapsed < 1.0, "elapsed=%f" % clock.elapsed)


## 人事 app 的行是按当天名单动态生成的。
func _test_personnel_rows() -> void:
	_section = "人事 app 动态行（_rebuild）"
	var roster: Array = _rm().current_round_employee_name_list
	var rows := _personnel_rows()

	_eq("行数", rows.size(), roster.size())
	if rows.size() != roster.size():
		return

	var pm := _node("personnel_manager")
	for i in range(rows.size()):
		var who: String = String(roster[i])
		_eq("行 %s 的按钮数" % who, rows[i].get_child_count() - 1, pm.ACTIONS.size())
		var shown := (rows[i].get_child(0) as Label).text
		_is_true("行 %s 上有名字" % who, not shown.is_empty())
	_eq("行数覆盖整份名单", rows.size(), roster.size())

	# 四个动作按钮印的符号：升职是职级的事用字母 P，加薪/减薪都是钱、靠箭头分方向。
	var page := _node("laptop_page/frame/pages/instruction_execute_page")
	for i in range(pm.ACTIONS.size()):
		var action: String = pm.ACTIONS[i]
		var b := rows[0].get_child(1 + i) as Button
		_eq("%s 按钮上的符号" % action, b.text, String(page.ACTION_LABELS[action]))
	_eq("Promotion 是字母 P", String(page.ACTION_LABELS["Promotion"]), "P")
	_eq("Raise 是 $ 加上箭头", String(page.ACTION_LABELS["Raise"]), "$↑")
	_eq("Reduction 是 $ 加下箭头", String(page.ACTION_LABELS["Reduction"]), "$↓")

	# UI 上按一下要真的写进 personnel_manager。
	var first_row: HBoxContainer = rows[0]
	var target: String = _row_name(first_row)
	var button: Button = first_row.get_child(1) as Button
	var before: bool = pm.is_set(target, pm.ACTIONS[0])
	button.button_pressed = not before
	_eq("按下按钮后数据层的值", pm.is_set(target, pm.ACTIONS[0]), not before)
	button.button_pressed = before
	_eq("弹回按钮后数据层的值", pm.is_set(target, pm.ACTIONS[0]), before)


## 活没干完不许下班：收件箱还有信的时候点门只弹提示，日子不会结束。
func _test_leave_blocked() -> void:
	_section = "活没干完不许下班"
	var reader := _node("email_reader")
	var notice := _node("notice_dialog")
	_is_true("收件箱还有信", reader.remaining() > 0)
	_is_false("提示一开始是关着的", notice.visible)

	SignalBus.object_clicked.emit(&"door")
	await _frames(2)

	_eq("回合状态没变", RoundState.current_round_state, RoundState.Round_State.GAME)
	_is_false("结算层没弹", _node("result_overlay").visible)
	_is_true("时钟还在走", _node("day_clock").is_processing())
	_is_true("提示弹出来了", notice.visible)
	_eq("提示文案", notice.get_node("%notice_bubble").get_node("%text_box").text,
		tr("UI_UNFINISHED"))

	notice._on_ok_pressed()
	await _windows_settled()
	_is_false("点 OK 关掉提示", notice.visible)

	# 只剩最后一封没读也一样锁着，不是「读过几封就算干完」。
	while reader.remaining() > 1:
		reader.read_next_email()
	SignalBus.object_clicked.emit(&"door")
	await _frames(2)
	_eq("还剩一封也走不了", RoundState.current_round_state, RoundState.Round_State.GAME)
	_is_true("又弹了一次提示", notice.visible)
	notice._on_ok_pressed()
	await _windows_settled()


## 全填对：不扣命，结算层显示满分。
func _test_settle_perfect_day() -> void:
	_section = "判分：全对（_settle_day）"
	var graded := _graded_count()
	_fill_correct()
	_eq("判分器算出的错误数", int(_node("personnel_manager").grade()["wrong"]), 0)

	var lives_before: int = _rm().lives
	_life_lost_events.clear()
	await _leave_office()
	await _frames(2)

	_eq("回合状态", RoundState.current_round_state, RoundState.Round_State.RESULT)
	_is_false("桌面可交互", RoundState.is_interactive())
	_is_false("时钟在走", _node("day_clock").is_processing())
	_eq("命数", _rm().lives, lives_before)
	_eq("扣命信号次数", _life_lost_events.size(), 0)

	var overlay := _node("result_overlay")
	_is_true("结算层可见", overlay.visible)
	_eq("结算层标题", overlay.get_node("%result_title").text,
		tr("UI_DAY_COUNT") % [1, _rm().days_to_win])
	# 分母是「判分的行数」——员工自己申请升职那种行不进分母。
	_eq("结算层对的数", overlay.get_node("%result_correct").text,
		"%d / %d" % [graded, graded])
	_eq("结算层错的数", overlay.get_node("%result_wrong").text, "0")
	_is_false("全对不挂 HR 那句", overlay.get_node("%result_note").visible)


## 全填错：错够 mistakes_per_life 就掉一条命，然后正常进下一天。
func _test_settle_bad_day_costs_life() -> void:
	_section = "判分：全错扣命 + 进次日"
	SignalBus.result_confirmed.emit()
	await _frames(2)
	_eq("次日天数", _rm().current_day, 2)
	_eq("次日回合状态", RoundState.current_round_state, RoundState.Round_State.STORY)
	_is_false("次日结算层可见", _node("result_overlay").visible)

	await _advance_to_game()
	_eq("次日收件箱封数", _node("email_reader").remaining(), _expected_mail_count())
	_eq("次日标准答案没串味", _keys_subset(_node("instruction_box").get_all(),
		_rm().current_round_employee_name_list), true)

	_fill_wrong()
	var wrong: int = int(_node("personnel_manager").grade()["wrong"])
	_eq("判分器算出的错误数", wrong, _graded_count())
	_is_true("错误数够扣命", wrong >= _rm().mistakes_per_life,
		"wrong=%d, 阈值=%d" % [wrong, _rm().mistakes_per_life])

	var lives_before: int = _rm().lives
	_life_lost_events.clear()
	await _leave_office()
	await _frames(2)

	_eq("命数", _rm().lives, lives_before - 1)
	_eq("扣命信号次数", _life_lost_events.size(), 1)
	if _life_lost_events.size() == 1:
		_eq("扣命信号带的剩余命数", _life_lost_events[0], lives_before - 1)
	_eq("结算层剩余命数", _node("result_overlay").get_node("%result_lives").text,
		tr("UI_LIVES_LEFT") % (lives_before - 1))
	_is_true("错了就挂 HR 那句", _node("result_overlay").get_node("%result_note").visible)


## 时间走到 18:00 会自己下班。
func _test_day_time_up() -> void:
	_section = "到点自动下班（day_time_up）"
	SignalBus.result_confirmed.emit()
	await _frames(2)
	await _advance_to_game()
	_eq("天数", _rm().current_day, 3)

	_is_true("信还没读完（到点下班不查这个）", _node("email_reader").remaining() > 0)

	var clock := _node("day_clock")
	_eq("上班时刻文本", clock.clock_text(), "%d:00" % clock.start_hour)
	clock.elapsed = clock.day_seconds - 0.001
	await _frames(4)

	_eq("回合状态", RoundState.current_round_state, RoundState.Round_State.RESULT)
	_is_false("时钟在走", clock.is_processing())
	_is_true("结算层可见", _node("result_overlay").visible)


## 存档往返：中途存盘 → 新建实例读档 → 数据和 UI 都要回到原样。
func _test_save_roundtrip() -> void:
	_section = "存档往返"
	SignalBus.result_confirmed.emit()
	await _frames(2)
	await _advance_to_game()

	# 造一个「干到一半」的现场：读掉两封信、填一部分表、时钟走了一段。
	var reader := _node("email_reader")
	reader.read_next_email()
	reader.read_next_email()
	_fill_correct()
	var pm := _node("personnel_manager")
	var roster: Array = _rm().current_round_employee_name_list
	pm.toggle(roster[0], pm.ACTIONS[0])   # 故意留一个错的，看它是否原样存回来
	_node("day_clock").elapsed = 42.5

	var before := {
		"day": _rm().current_day,
		"lives": _rm().lives,
		"roster": roster.duplicate(),
		"elapsed": _node("day_clock").elapsed,
		"assignments": pm.assignments.duplicate(true),
		"unread": _unread_signature(),
		"truth": _truth_signature(),
		"grade": pm.grade(),
	}

	_is_true("存盘成功", SaveState.save_game())
	await _spawn_scene(true)

	_eq("天数", _rm().current_day, before["day"])
	_eq("命数", _rm().lives, before["lives"])
	_eq("名单", _rm().current_round_employee_name_list, before["roster"])
	_eq("回合状态", RoundState.current_round_state, RoundState.Round_State.GAME)
	_is_true("时钟接着走", _node("day_clock").is_processing())
	# 读档之后时钟马上又跑起来了，所以只要求「不早于存盘那一刻、且没跳走一大截」。
	var elapsed_now: float = _node("day_clock").elapsed
	var elapsed_saved: float = before["elapsed"]
	_is_true("剩余时间", elapsed_now >= elapsed_saved and elapsed_now < elapsed_saved + 1.0,
		"elapsed=%f，存的是 %f" % [elapsed_now, elapsed_saved])
	_eq("已填的表", _node("personnel_manager").assignments, before["assignments"])
	_eq("未读邮件", _unread_signature(), before["unread"])
	_eq("标准答案", _truth_signature(), before["truth"])
	_eq("判分结果", _node("personnel_manager").grade(), before["grade"])
	_is_false("剧情层可见", _node("story_page").visible)

	# 人事 app 的行也要按恢复出来的表重铺，不然玩家看到的是空表。
	var rows := _personnel_rows()
	_eq("行数", rows.size(), before["roster"].size())
	var mismatched := 0
	for row in rows:
		var employee: String = _row_name(row)
		for i in range(_node("personnel_manager").ACTIONS.size()):
			var action: String = _node("personnel_manager").ACTIONS[i]
			var button := row.get_child(1 + i) as Button
			if button.button_pressed != _node("personnel_manager").is_set(employee, action):
				mismatched += 1
	_eq("按钮状态和表对不上的格子数", mismatched, 0)


## 每天的升职名额：默认一天只能给一个人升职，超了那一下会被挡掉并弹提示。
func _test_promotion_quota() -> void:
	_section = "升职名额"
	await _spawn_scene(false)
	await _advance_to_game()

	var rm := _rm()
	var pm := _node("personnel_manager")
	var roster: Array = rm.current_round_employee_name_list
	_eq("默认一天一个", rm.promotions_per_day, 1)
	if roster.size() < 2:
		_record("名单至少两个人", false, "实际 %d" % roster.size())
		return

	var notices: Array = []
	var conn := func(text: String) -> void: notices.append(text)
	SignalBus.notice_requested.connect(conn)

	# 第一个人：正常填得进去。
	_is_true("第一个升职填得进去", pm.toggle(roster[0], "Promotion"))
	_eq("已用名额", pm.promotions_used(), 1)
	_eq("没弹提示", notices.size(), 0)

	# 第二个人：名额没了，数据层一动不动。
	_is_false("第二个升职被挡掉", pm.toggle(roster[1], "Promotion"))
	_is_false("第二个人没被写进表", pm.is_set(roster[1], "Promotion"))
	_eq("已用名额没变", pm.promotions_used(), 1)
	_eq("弹了一条提示", notices.size(), 1)
	_has_text("提示里写了名额数", str(notices[0]) if notices.size() > 0 else "", "1")

	# 名额限的只是升职，别的动作照填。
	_is_true("加薪不受名额限制", pm.toggle(roster[1], "Raise"))

	# 把第一个人的升职取消，名额就回来了。
	_is_true("取消不会被挡", pm.toggle(roster[0], "Promotion"))
	_eq("名额回来了", pm.promotions_used(), 0)
	_is_true("现在轮到第二个人升得了", pm.toggle(roster[1], "Promotion"))

	# UI 层：被挡掉的那一下按钮要弹回去，不能表上勾着、数据里没有。
	pm.begin_day()
	SignalBus.round_state_change.emit(RoundState.Round_State.GAME)
	await _frames(2)
	var rows := _personnel_rows()
	var promo_index: int = pm.ACTIONS.find("Promotion")
	var first_button := rows[0].get_child(1 + promo_index) as Button
	var second_button := rows[1].get_child(1 + promo_index) as Button
	first_button.button_pressed = true
	await _frames(1)
	_is_true("UI 上第一个人升职生效", pm.is_set(_row_name(rows[0]), "Promotion"))
	second_button.button_pressed = true
	await _frames(1)
	_is_false("UI 上第二个人的数据没被改", pm.is_set(_row_name(rows[1]), "Promotion"))
	_is_false("按钮也弹回去了", second_button.button_pressed)

	# 名额改大 / 关掉限制。
	rm.promotions_per_day = 2
	_is_true("名额放宽后第二个人填得进去", pm.toggle(_row_name(rows[1]), "Promotion"))
	_eq("已用两个", pm.promotions_used(), 2)
	rm.promotions_per_day = -1
	_is_true("-1 = 不限制", pm.toggle(_row_name(rows[2]), "Promotion"))
	_eq("三个都填上了", pm.promotions_used(), 3)
	rm.promotions_per_day = 1

	SignalBus.notice_requested.disconnect(conn)

	# 随机信不该凑出填不下的标准答案，否则这一天永远拿不到满分。
	for i in range(4):
		await _spawn_scene(false)
		await _advance_to_game()
		_is_true("第 %d 次开工：标准答案里的升职人数不超名额" % (i + 1),
			_truth_promotions() <= _rm().promotions_per_day,
			"要求升职 %d 人，名额 %d" % [_truth_promotions(), _rm().promotions_per_day])


## 标准答案里有几个人要升职。
func _truth_promotions() -> int:
	var count := 0
	var truth: Dictionary = _node("instruction_box").get_all()
	for name in truth:
		if bool(truth[name].has_promotion):
			count += 1
	return count


## 这一行是谁（**标识**，不是表上显示的名字——那个是翻译过的）。
## 行是按 roster() 顺序铺的，所以下标就能对上。
func _row_name(row: Node) -> String:
	var rows := _personnel_rows()
	var at := rows.find(row)
	var roster: Array = _node("personnel_manager").roster()
	return String(roster[at]) if at >= 0 and at < roster.size() else ""


## 桌上那本记事本：玩家自己写的东西，能翻页、有字数上限、进存档、不跨局。
func _test_notes_pad() -> void:
	_section = "记事本"
	await _spawn_scene(false)
	await _advance_to_game()

	var pad := _node("notes_page")
	_is_false("一开始没打开", pad.visible)

	SignalBus.open_notes_request.emit()
	await _windows_settled()
	_is_true("点便签打开了", pad.visible)
	_eq("从第 1 页起手", pad.page, 0)
	_has_text("页码显示", _node("%note_page_label").text, "1 / 5")

	# 第 1 页印着电脑的账号密码——邮件阅后即焚，这是玩家唯一查得回去的地方。
	_eq("第 1 行是用户名", _node("%note_line_0").text, "hrtemp")

	# 印的是这一局真正生效的那一组：用户名来自 world.story，
	# 密码是开局摇出来的（每局都不一样，背不下来）。
	# 场景 @export 会被编辑器重存抹掉（已中招两次），所以这两行不能另抄一份。
	var first_user := String(_node("story_book").world.accounts[0].username)
	var first_pass := GameState.account_password(_node("story_book").world.accounts[0].username)
	_eq("用户名跟着 world.story 走", _node("%note_line_0").text, first_user)
	_eq("密码是这一局的那个", _node("%note_line_1").text, first_pass)
	_eq("密码是 4 位", first_pass.length(), 4)
	_is_true("密码是数字", first_pass.is_valid_int())
	_is_true("用户名塞得进一行", first_user.length() <= pad.MAX_CHARS)
	_is_true("密码塞得进一行", first_pass.length() <= pad.MAX_CHARS)
	_eq("每行最多 6 个字符", _node("%note_line_0").max_length, pad.MAX_CHARS)

	# 记事本要能打开着看邮件——它不走 WindowManager，不会被笔记本顶掉。
	SignalBus.open_laptop_request.emit()
	await _windows_settled()
	_is_true("开笔记本不会把记事本关掉", pad.visible)
	await WindowManager.close_current(_scene)
	await _windows_settled()

	# 玩家自己写一行，翻页再翻回来还在。
	_node("%note_line_2").text = "Mira"
	_node("%note_line_2").text_changed.emit("Mira")
	pad._on_next_pressed()
	_eq("翻到第 2 页", pad.page, 1)
	_eq("第 2 页是空的", _node("%note_line_2").text, "")
	_node("%note_line_0").text = "fire"
	_node("%note_line_0").text_changed.emit("fire")
	pad._on_prev_pressed()
	_eq("翻回第 1 页", pad.page, 0)
	_eq("第 1 页写的还在", _node("%note_line_2").text, "Mira")

	# 翻页不循环：到头就停住，按钮也灰掉。
	pad._on_prev_pressed()
	_eq("第 1 页再往前还是第 1 页", pad.page, 0)
	_is_true("上一页按钮灰了", _node("%note_prev").disabled)
	for i in range(10):
		pad._on_next_pressed()
	_eq("翻到底停在最后一页", pad.page, pad.PAGES - 1)
	_is_true("下一页按钮灰了", _node("%note_next").disabled)

	_is_true("存盘成功", SaveState.save_game())

	# 读档回来：玩家写的东西一个字都不能少。
	await _spawn_scene(true)
	var restored := _node("notes_page")
	_eq("第 1 页第 3 行读回来了", restored._line(0, 2), "Mira")
	_eq("第 2 页第 1 行读回来了", restored._line(1, 0), "fire")
	_eq("读档后回到第 1 页", restored.page, 0)

	# 开新局是新建场景，本子回到初始状态（只剩印好的账号密码）。
	await _spawn_scene(false)
	var fresh := _node("notes_page")
	_eq("新局第 1 页第 1 行", fresh._line(0, 0), "hrtemp")
	_eq("新局不留上一局写的东西", fresh._line(0, 2), "")


## 一路全对撑到最后一天 → 通关。
func _test_clear_run() -> void:
	_section = "通关（game_cleared）"
	await _spawn_scene(false)
	_game_cleared_count = 0
	_game_over_count = 0

	var days: int = _rm().days_to_win
	for i in range(days):
		await _advance_to_game()
		_eq("第 %d 天的天数" % (i + 1), _rm().current_day, i + 1)
		_fill_correct()
		await _leave_office()
		await _frames(2)
		SignalBus.result_confirmed.emit()
		await _frames(2)

	_eq("满命通关", _rm().lives, _rm().max_lives)
	_eq("通关信号次数", _game_cleared_count, 1)
	_eq("开除信号次数", _game_over_count, 0)

	# 通关之后先摊五天的人事调动日志，玩家点继续才给结局。
	var log_layer := _node("log_overlay")
	_is_true("日志层可见", log_layer.visible)
	_is_true("日志有条目", log_layer.get_node("%log_list").get_child_count() > 0)

	var ending := _node("ending_overlay")
	_is_false("看日志时结局层还没出来", ending.visible)

	log_layer._on_continue_pressed()
	await _frames(2)
	_is_false("日志层收起", log_layer.visible)
	_is_true("结局层可见", ending.visible)
	# 全程照章办事 = 第二天把随机员工全 fire 了（A+2）、第五天批了瑞克的 promotion，
	# 所以「满分通关」走的是结局 A。听话本身就是一种选择。
	_eq("结局标题", ending.get_node("%ending_title").text,
		_node("ending_director").def_for(GameState.SCORE_A).title)


## 一路全错把命扣光 → 被开除，而且不会同时报通关。
func _test_fired_run() -> void:
	_section = "被开除（game_over）"
	await _spawn_scene(false)
	_game_cleared_count = 0
	_game_over_count = 0

	var max_days: int = _rm().max_lives + 2   # 兜底，正常在扣光命时就出结局
	for i in range(max_days):
		if _game_over_count > 0:
			break
		await _advance_to_game()
		_fill_wrong()
		await _leave_office()
		await _frames(2)
		SignalBus.result_confirmed.emit()
		await _frames(2)

	_eq("命数", _rm().lives, 0)
	# **不是每天必掉一条命**：一天错够 mistakes_per_life 个人才扣命，而人事表上
	# 只有「今天真被提到的人」——剧情信少、随机信也少的日子（第 4、5 天）判分的行
	# 可能不到阈值，那天全错也不掉命。所以撑几天是浮动的，只能卡个范围。
	_is_true("至少撑到第 %d 天" % _rm().max_lives, _rm().current_day >= _rm().max_lives,
		"撑到第 %d 天" % _rm().current_day)
	_is_true("撑不过最后一天", _rm().current_day <= _rm().days_to_win,
		"撑到第 %d 天" % _rm().current_day)
	_eq("开除信号次数", _game_over_count, 1)
	_eq("通关信号次数", _game_cleared_count, 0)

	var ending := _node("ending_overlay")
	_is_true("结局层可见", ending.visible)
	_is_false("被开除不摊日志", _node("log_overlay").visible)
	_eq("结局标题", ending.get_node("%ending_title").text,
		_node("ending_director").def_for(&"E").title)


## 游戏内的设置入口：右上角齿轮开的和菜单里是同一个 settings_panel.tscn，
## 而且要走 WindowManager——不然它会和笔记本、日历同时开着。
func _test_ingame_settings() -> void:
	_section = "游戏内设置入口"
	await _spawn_scene(false)

	var panel := _node("settings_panel")
	_is_true("设置面板在场景里", panel != null)
	_is_true("是 popup_window", panel is popup_window)
	_is_false("一开始是关着的", panel.visible)
	_is_true("滑块也一起实例化了", panel.get_node_or_null("%bgm_slider") != null)

	_scene._on_settings_pressed()
	await _windows_settled()
	_is_true("齿轮把面板开起来了", panel.visible)
	_eq("管理器记着它开着", WindowManager.get_current(_scene), panel)

	# 开笔记本要把设置顶掉：同一个场景里只能开一个窗口。
	SignalBus.open_laptop_request.emit()
	await _windows_settled()
	_is_false("开笔记本时设置收起来了", panel.visible)
	_eq("管理器改记笔记本", WindowManager.get_current(_scene), _node("laptop_page"))

	WindowManager.close_current(_scene)
	await _windows_settled()
	_is_false("全关掉了", _node("laptop_page").visible)


## 菜单往返。Resume 有两条路，都要走一遍：
##   1. 这次会话里回过菜单 → 复用挂起的实例，连 UI 状态都原样
##   2. 关过程序 → 新建实例，从磁盘存档灌数据
func _test_menu_roundtrip() -> void:
	_section = "菜单往返"
	await _despawn_scene()
	SaveState.clear()
	SceneTransition.clear_retained()

	SceneTransition.goto(MENU_SCENE, SceneTransition.Slide.NONE)
	await _await_transition(MENU_SCENE)
	var menu: Node = SceneTransition.current_scene
	_is_true("没存档时「继续」是灰的", _continue_button(menu).disabled)

	# ── New Start ──
	menu._on_new_game_pressed()
	await _await_transition(MAIN_SCENE)
	_scene = SceneTransition.current_scene
	await _frames(2)
	_eq("新开局天数", _rm().current_day, 1)
	_eq("新开局命数", _rm().lives, _rm().max_lives)

	await _advance_to_game()
	_fill_correct()
	_node("day_clock").elapsed = 30.0
	var roster: Array = _rm().current_round_employee_name_list.duplicate()
	var assignments: Dictionary = _node("personnel_manager").assignments.duplicate(true)
	var unread: Array = _unread_signature()
	var played_instance: Node = _scene

	# ── 点「回主菜单」：存盘 + 挂起 ──
	_node("back_to_menu")._on_pressed()
	await _await_transition(MENU_SCENE)
	menu = SceneTransition.current_scene
	_is_true("挂起了游戏实例", SceneTransition.has_retained(MAIN_SCENE))
	_is_true("写了磁盘存档", SaveState.has_save())
	_is_false("有进度时「继续」可点", _continue_button(menu).disabled)

	# ── Resume 走挂起的实例 ──
	menu._on_continue_pressed()
	await _await_transition(MAIN_SCENE)
	_scene = SceneTransition.current_scene
	await _frames(2)
	_is_true("复用的是同一个实例", _scene == played_instance)
	_eq("名单", _rm().current_round_employee_name_list, roster)
	_eq("已填的表", _node("personnel_manager").assignments, assignments)
	_eq("未读邮件", _unread_signature(), unread)
	_eq("回合状态", RoundState.current_round_state, RoundState.Round_State.GAME)
	_is_true("时钟接着走", _node("day_clock").is_processing())

	# ── 再回菜单，丢掉挂起实例，逼它走磁盘存档 ──
	_node("back_to_menu")._on_pressed()
	await _await_transition(MENU_SCENE)
	menu = SceneTransition.current_scene
	SceneTransition.discard(MAIN_SCENE)
	await _frames(2)
	_is_false("丢掉后还有挂起实例", SceneTransition.has_retained(MAIN_SCENE))
	_is_true("磁盘存档还在", SaveState.has_save())

	menu._on_continue_pressed()
	await _await_transition(MAIN_SCENE)
	_scene = SceneTransition.current_scene
	await _frames(2)
	_is_false("是新实例", _scene == played_instance)
	_eq("名单", _rm().current_round_employee_name_list, roster)
	_eq("已填的表", _node("personnel_manager").assignments, assignments)
	_eq("未读邮件", _unread_signature(), unread)
	_eq("回合状态", RoundState.current_round_state, RoundState.Round_State.GAME)
	_is_true("时钟接着走", _node("day_clock").is_processing())
	_is_true("剩余时间", _node("day_clock").elapsed >= 30.0, "elapsed=%f" % _node("day_clock").elapsed)
	_is_false("剧情层可见", _node("story_page").visible)
	_eq("人事表行数", _personnel_rows().size(), roster.size())

	# 这一局是路由器持有的，别让 _despawn_scene 去 remove_child 别人的孩子。
	_scene = null


func _continue_button(menu: Node) -> Button:
	return menu.get_node("background/VBoxContainer/continue_button") as Button


## 等转场落到指定场景。用挂钟兜底，goto 提前返回（重复路径 / 正忙）时不会把测试挂死。
func _await_transition(expected_path: String) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if SceneTransition.current_path == expected_path and not SceneTransition._busy:
			break
		await get_tree().process_frame
	_record("转场落到 %s" % expected_path.get_file(),
		SceneTransition.current_path == expected_path and not SceneTransition._busy,
		"current_path=%s, busy=%s" % [SceneTransition.current_path, SceneTransition._busy])


# ── 场景装卸 ────────────────────────────────────────────

func _spawn_scene(restoring: bool) -> void:
	await _despawn_scene()
	if restoring:
		SaveState.begin_restore()
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


func _advance_to_game() -> void:
	SignalBus.story_finished.emit()
	await _frames(2)


## 窗口开关带动画（popup_window 的 tween），等帧不够，得等真时间。
func _windows_settled() -> void:
	await get_tree().create_timer(0.6).timeout


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


# ── 场景里的节点 ────────────────────────────────────────

func _node(path: String) -> Node:
	return _scene.get_node(path)


func _rm() -> Node:
	return _node("round_manager")


func _personnel_rows() -> Array:
	var list := _node("laptop_page/frame/pages/instruction_execute_page/VBoxContainer/personnel_list")
	var rows: Array = []
	for c in list.get_children():
		# queue_free 掉的旧行要到帧末才真的消失，这里只数活着的。
		if not c.is_queued_for_deletion():
			rows.append(c)
	return rows


# ── 打表用的辅助 ────────────────────────────────────────

## 主动下班。收件箱没清空的话门是锁着的（见 _test_leave_blocked），
## 所以先把信全读了再去点门。
func _leave_office() -> void:
	var reader := _node("email_reader")
	while reader.remaining() > 0:
		reader.read_next_email()
	SignalBus.object_clicked.emit(&"door")
	await _frames(2)


## 按当天标准答案把表填满（满分打法）。
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


## 每个人都恰好错一格，保证错误数等于当天人数。
func _fill_wrong() -> void:
	_fill_correct()
	var pm := _node("personnel_manager")
	for employee_name in _rm().current_round_employee_name_list:
		pm.toggle(employee_name, pm.ACTIONS[0])


## 当天有几个剧情角色进表（day_plan 的 roster + 剧情信点名下令的人）。
func _story_roster_size() -> int:
	var plan = _node("story_book").plan_for(_rm().current_day)
	if plan == null:
		return 0
	var names: Array = []
	for n in plan.story_roster:
		if not String(n).is_empty() and not names.has(String(n)):
			names.append(String(n))
	for m in plan.scripted_emails:
		if m == null or m.targets_all_random():
			continue
		var t := String(m.target_employee)
		if not t.is_empty() and not names.has(t):
			names.append(t)
	return names.size()


## 当天判分的行数（不判分的行不进分母）。
func _graded_count() -> int:
	var pm := _node("personnel_manager")
	var count := 0
	for name in _rm().current_round_employee_name_list:
		if pm.is_graded(name):
			count += 1
	return count


## 当天该收几封信 = 剧情信 + 填充信。没配 day_plan 的天就是老样子（emails_per_day）。
func _expected_mail_count() -> int:
	var rm := _rm()
	var plan = _node("story_book").plan_for(rm.current_day)
	if plan == null:
		return rm.emails_per_day
	var filler: int = plan.filler_emails if plan.filler_emails >= 0 else rm.emails_per_day
	var scripted := 0
	for m in plan.scripted_emails:
		if m == null or not m.should_send():
			continue
		# order=fire:*random 会展开成「一个随机员工一封」。
		scripted += rm.current_random_name_list.size() if m.targets_all_random() else 1
	return filler + scripted


func _unread_signature() -> Array:
	var out: Array = []
	for e in _node("email_reader").unread_email:
		out.append("%s|%s|%d" % [e.target_employee_name, e.instruction, e.sender_class])
	return out


func _truth_signature() -> Dictionary:
	var out: Dictionary = {}
	for employee_name in _node("instruction_box").get_all():
		out[employee_name] = _node("instruction_box").get_all()[employee_name].get_final_state()
	return out


func _unique(a: Array) -> Array:
	var out: Array = []
	for v in a:
		if not (v in out):
			out.append(v)
	return out


func _keys_subset(d: Dictionary, allowed: Array) -> bool:
	for k in d:
		if not (k in allowed):
			return false
	return true


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
	print("\n================ flow_test ================")
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
