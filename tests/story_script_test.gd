extends Node

## `.story` 剧本格式的自测：语法逐条覆盖、坏语法报对行号、真内容文件解析对不对。
##
## 跑法（项目根目录）：
##     <godot> --headless --path . res://tests/story_script_test.tscn
## 退出码 0 全过，非 0 有失败项。
##
## 解析器不依赖编辑器，所以这里直接喂字符串；最后一段才去读真的
## story/world.story 和 story/days/day_1.story（那两个走的是导入器）。

const WORLD_PATH := "res://story/zh/world.story"
const DAY_1_PATH := "res://story/zh/days/day_1.story"

var _passed := 0
var _failed := 0
var _fail_lines: Array[String] = []
var _section := ""


func _ready() -> void:
	_test_dialogue()
	_test_choices_and_effects()
	_test_mail()
	_test_day_and_events()
	_test_world()
	_test_conditions()
	_test_condition_blocks()
	_test_score_block()
	_test_caller_interpolation()
	_test_contacts()
	_test_errors()
	_test_real_files()
	_test_locales_match()
	_report()


# ── 对话 ────────────────────────────────────────────────

func _test_dialogue() -> void:
	_section = "对话块"
	var r := story_parser.parse("""
[story]
them: One.
me: Two.
them!: Three.
still three
""", "t.story")
	_no_errors(r)
	if r.day == null:
		return

	var d: dialogue = r.day.story.dialogues[0]
	_eq("段落 id 默认是 start", d.id, &"start")
	_eq("气泡数", d.bubbles.size(), 3)
	if d.bubbles.size() < 3:
		return
	_eq("第一条是对方", d.bubbles[0].side, conversation_bubble.Side.THEIRS)
	_eq("第一条文字", d.bubbles[0].text, "One.")
	_eq("第二条是我方", d.bubbles[1].side, conversation_bubble.Side.MINE)
	_is_true("默认可以跳字", d.bubbles[0].can_skip)
	_is_false("叹号 = 不许跳字", d.bubbles[2].can_skip)
	_eq("续行接在上一条后面", d.bubbles[2].text, "Three.\nstill three")


func _test_choices_and_effects() -> void:
	_section = "选项与效果"
	var r := story_parser.parse("""
[story]
them: Pick.
- "Jump" -> goto=other, A+1, flag=picked_jump
- "Stay" -> C-2

[dialogue other]
them: Jumped.
""", "t.story")
	_no_errors(r)
	if r.day == null:
		return

	var c: conversation = r.day.story
	_eq("两个段落", c.dialogues.size(), 2)
	_eq("第二段的 id", c.dialogues[1].id, &"other")

	var b: conversation_bubble = c.dialogues[0].bubbles[0]
	_eq("选项数", b.choices.size(), 2)
	if b.choices.size() < 2:
		return
	_eq("选项文字", b.choices[0].text, "Jump")
	_eq("goto", b.choices[0].goto, &"other")
	_eq("A 增量", b.choices[0].effect.a_delta, 1)
	_eq("flag", b.choices[0].effect.set_flags, [&"picked_jump"] as Array[StringName])
	_eq("负增量", b.choices[1].effect.c_delta, -2)
	_eq("没写 goto 就是空", b.choices[1].goto, &"")


# ── 邮件 ────────────────────────────────────────────────

func _test_mail() -> void:
	_section = "邮件块"
	var r := story_parser.parse("""
[mail welcome from="Renn, Ops" faction=B order=raise:Mira class=3 about=Mira]
subject: Welcome
Line one.
Note: this colon line is body, not a header.
- "Thanks" -> B+1, echo="You thanked him."
- "Noted" ->
""", "t.story")
	_no_errors(r)
	if r.day == null or r.day.scripted_emails.is_empty():
		return

	var m: email_def = r.day.scripted_emails[0]
	_eq("id", m.id, &"welcome")
	_eq("发件人（引号里的逗号不切开）", m.sender_name, "Renn, Ops")
	_eq("派系", m.sender_faction, faction.Id.B)
	_eq("指令", m.order, email_def.Order.RAISE)
	_eq("指令对象", m.target_employee, &"Mira")
	_eq("发件人等级", m.sender_class, 3)
	_eq("关联员工", m.about_employee, &"Mira")
	_eq("标题", m.subject, "Welcome")
	_eq("正文（带冒号的行也算正文）", m.body_text(),
		"Line one.\nNote: this colon line is body, not a header.")
	_eq("回复数", m.replies.size(), 2)
	if m.replies.size() < 2:
		return
	_eq("回复的立场", m.replies[0].effect.b_delta, 1)
	_eq("回显", m.replies[0].effect.reply_echo, "You thanked him.")
	_is_true("没写效果也有个空 effect", m.replies[1].effect != null)
	_is_true("空效果就是空", m.replies[1].effect.is_empty())


func _test_day_and_events() -> void:
	_section = "[day] 与桥段块"
	var r := story_parser.parse("""
[day]
filler: 2
roster: Mira, Jack

[caller]
them: Ring.
- "Keep it." -> flag=took_the_call

[electricbox]
them: Breakers.

[window]
them: Glass.
""", "t.story")
	_no_errors(r)
	if r.day == null:
		return

	_eq("填充信封数", r.day.filler_emails, 2)
	_eq("点名的剧情角色", r.day.story_roster, [&"Mira", &"Jack"] as Array[StringName])
	_is_true("电话有内容", r.day.caller != null and not r.day.caller.is_empty())
	_is_true("电箱有内容", r.day.electricbox != null)
	_is_true("窗户有内容", r.day.window != null)
	_is_true("没写 [story] 时开场为空", r.day.story == null)
	_eq("桥段里的选项也进得去",
		r.day.caller.dialogues[0].bubbles[-1].choices[0].effect.set_flags,
		[&"took_the_call"] as Array[StringName])

	# 便签没有块：桌上那本是玩家自己写的记事本，不播对话。
	var no_notes := story_parser.parse("[notes]\nthem: hi\n", "t.story")
	_is_true("[notes] 不再是合法的块", not no_notes.ok())


func _test_world() -> void:
	_section = "world 块"
	var r := story_parser.parse("""
[account hr_temp]
pass: 4471
name: Temp HR
clearance: 1

[profile Mira]
position: Line supervisor
department: Floor 3
faction: GROUND
clearance: 2
First line.

Second paragraph.
""", "w.story")
	_no_errors(r)
	if r.world == null:
		return

	_is_true("产的是 world 不是 day", r.day == null)
	_eq("账户数", r.world.accounts.size(), 1)
	_eq("档案数", r.world.profiles.size(), 1)
	if r.world.accounts.is_empty() or r.world.profiles.is_empty():
		return

	var a: account = r.world.accounts[0]
	_eq("用户名", a.username, &"hr_temp")
	_eq("密码", a.password, "4471")
	_eq("显示名", a.display_name, "Temp HR")
	_eq("权限等级", a.clearance, 1)
	_is_true("密码对得上", a.matches("hr_temp", "4471"))
	_is_true("用户名不分大小写", a.matches("HR_TEMP", "4471"))
	_is_false("密码错了就是错了", a.matches("hr_temp", "4472"))

	var p: employee_profile = r.world.profiles[0]
	_eq("员工名", p.employee_name, &"Mira")
	_eq("职位", p.position, "Line supervisor")
	_eq("部门", p.department, "Floor 3")
	_eq("派系", p.employee_faction, faction.Id.GROUND)
	_eq("档案等级", p.clearance, 2)
	_eq("正文保留空行分段", p.body, "First line.\n\nSecond paragraph.")


# ── 条件 ────────────────────────────────────────────────

## 条件求值器：每种原子各来一条。
func _test_conditions() -> void:
	_section = "条件求值"
	GameState.reset()
	GameState.day = 3
	GameState.add_score(GameState.SCORE_A, 2)
	GameState.levels[&"Bob"] = 3
	GameState.set_flag(&"took_the_call")
	GameState.mark_called(&"Mira")
	# 第 1 天给鲍勃批过 promotion，第 3 天 fire 了两个随机员工里的一个。
	GameState.log_personnel(1, {"employee": "Bob", "actual": {"Promotion": true}, "random": false})
	GameState.log_personnel(3, {"employee": "Jack", "actual": {"Fire": true}, "random": true})
	GameState.log_personnel(3, {"employee": "Kate", "actual": {"Fire": false}, "random": true})

	_is_true("空条件永远成立", story_condition.eval(""))
	_is_true("score.A>=2", story_condition.eval("score.A>=2"))
	_is_false("score.A>=3", story_condition.eval("score.A>=3"))
	_is_true("score.B==0", story_condition.eval("score.B==0"))
	_is_true("level.Bob>=3", story_condition.eval("level.Bob>=3"))
	_is_false("没档案的人 level 是 -1", story_condition.eval("level.Nobody>=0"))
	_is_true("day>=3", story_condition.eval("day>=3"))
	_is_true("flag:took_the_call", story_condition.eval("flag:took_the_call"))
	_is_false("没打开的 flag", story_condition.eval("flag:nope"))
	_is_true("called(Mira)", story_condition.eval("called(Mira)"))
	_is_false("没打过的电话", story_condition.eval("called(Bob)"))

	# did 默认只看今天（day=3）。
	_is_true("did(fire,Jack) 今天", story_condition.eval("did(fire,Jack)"))
	_is_false("did(promote,Bob) 今天没有", story_condition.eval("did(promote,Bob)"))
	_is_true("did(promote,Bob,day1)", story_condition.eval("did(promote,Bob,day1)"))
	_is_true("did(promote,Bob,ever)", story_condition.eval("did(promote,Bob,ever)"))
	_is_true("did(fire,*any) 今天至少一个", story_condition.eval("did(fire,*any)"))
	_is_false("did(fire,*random) 没有全部", story_condition.eval("did(fire,*random)"))

	# 换一天：那天两个随机员工都被 fire 了。
	GameState.log_personnel(4, {"employee": "Jack", "actual": {"Fire": true}, "random": true})
	GameState.log_personnel(4, {"employee": "Kate", "actual": {"Fire": true}, "random": true})
	GameState.day = 4
	_is_true("那天所有随机员工都 fire 了", story_condition.eval("did(fire,*random)"))
	GameState.day = 3

	_is_true("not 取反", story_condition.eval("not score.A>=5"))
	_is_true("and 串联", story_condition.eval("score.A>=2 and flag:took_the_call"))
	_is_false("and 有一个不成立就不成立", story_condition.eval("score.A>=2 and flag:nope"))
	_is_true("not + and", story_condition.eval("not flag:nope and day>=3"))

	GameState.reset()


## `?if ... ?end` 和选项自己的 if=。
func _test_condition_blocks() -> void:
	_section = "条件块"
	var r := story_parser.parse("""
[mail m1 from=\"X\" if=score.A>=2]
subject: S
always
?if level.Bob>=3
only when bob is senior
?end
tail

[story]
them: one
?if flag:x
them: hidden
?end
them: two
- \"always\" -> A+1
- \"only sometimes\" if=flag:x -> B+1
""", "t.story")
	_no_errors(r)
	if r.day == null or r.day.scripted_emails.is_empty():
		return

	var m: email_def = r.day.scripted_emails[0]
	_eq("整封信的条件", m.condition, "score.A>=2")
	_eq("正文分了三段", m.body_blocks.size(), 3)
	if m.body_blocks.size() == 3:
		_eq("第一段无条件", m.body_blocks[0].condition, "")
		_eq("第二段带条件", m.body_blocks[1].condition, "level.Bob>=3")
		_eq("第三段又回到无条件", m.body_blocks[2].condition, "")
		_eq("第二段的文字", m.body_blocks[1].text, "only when bob is senior")

	var bubbles: Array[conversation_bubble] = r.day.story.dialogues[0].bubbles
	_eq("三条气泡", bubbles.size(), 3)
	if bubbles.size() == 3:
		_eq("普通气泡没有条件", bubbles[0].condition, "")
		_eq("包起来的气泡带条件", bubbles[1].condition, "flag:x")
		_eq("?end 之后恢复", bubbles[2].condition, "")

	var choices: Array[conversation_choice] = bubbles[-1].choices
	_eq("两个选项", choices.size(), 2)
	if choices.size() == 2:
		_eq("第一个选项无条件", choices[0].condition, "")
		_eq("第二个选项带条件", choices[1].condition, "flag:x")


## [score] 块。
func _test_score_block() -> void:
	_section = "[score] 日终结算块"
	var r := story_parser.parse("""
[score]
if did(fire,*random) -> A+2
if not did(fire,*any) -> C+2, flag=stayed_clean
""", "t.story")
	_no_errors(r)
	if r.day == null:
		return

	_eq("两条规则", r.day.score_rules.size(), 2)
	if r.day.score_rules.size() < 2:
		return
	_eq("第一条的条件", r.day.score_rules[0].condition, "did(fire,*random)")
	_eq("第一条加 A+2", r.day.score_rules[0].effect.a_delta, 2)
	_eq("第二条的条件", r.day.score_rules[1].condition, "not did(fire,*any)")
	_eq("第二条加 C+2", r.day.score_rules[1].effect.c_delta, 2)
	_eq("第二条还打了 flag", r.day.score_rules[1].effect.set_flags,
		[&"stayed_clean"] as Array[StringName])


## {caller:X} 换成这一局的号码。
func _test_caller_interpolation() -> void:
	_section = "号码占位符"
	GameState.reset()
	_eq("还没有号码时显示占位", story_text.resolve("call {caller:Mira}"),
		"call %s" % story_text.UNKNOWN)

	GameState.caller_numbers[&"Mira"] = "4471"
	GameState.caller_numbers[&"Bob"] = "8250"
	_eq("换成真号码", story_text.resolve("call {caller:Mira}"), "call 4471")
	_eq("一行里两个也换", story_text.resolve("{caller:Mira} / {caller:Bob}"), "4471 / 8250")
	_eq("没有占位符就原样返回", story_text.resolve("plain text"), "plain text")
	GameState.reset()


## [contact] / [call] / repeat=yes
func _test_contacts() -> void:
	_section = "联系人与通话"
	var r := story_parser.parse("""
[contact Mira]
name: Mira, floor 3

[call Mira]
them: hello?
- \"ask about the box\" -> C+1

[contact desk]
number: 1234
""", "w.story")
	_no_errors(r)
	if r.world == null:
		return

	_eq("两个联系人", r.world.contacts.size(), 2)
	if r.world.contacts.size() < 2:
		return
	var mira: contact = r.world.contacts[0]
	_eq("联系人名", mira.contact_name, &"Mira")
	_eq("显示名", mira.display_name, "Mira, floor 3")
	_is_true("号码留空 = 随机", mira.fixed_number.is_empty())
	_is_true("挂上了通话内容", mira.call != null and not mira.call.is_empty())
	_eq("通话里的选项也能加分",
		mira.call.dialogues[0].bubbles[0].choices[0].effect.c_delta, 1)
	_eq("写死的号码保留", String(r.world.contacts[1].fixed_number), "1234")
	_eq("没写 name 就用内部名", r.world.contacts[1].label(), "desk")

	# [call] 必须跟在同名 [contact] 后面。
	var orphan := story_parser.parse("[call Nobody]\nthem: hi\n", "w.story")
	_is_true("找不到联系人要报错", not orphan.ok())

	# 桥段的 repeat=yes
	var day := story_parser.parse("""
[electricbox repeat=yes]
them: the box.

[caller]
them: ring.
""", "d.story")
	_no_errors(day)
	if day.day != null:
		_is_true("电箱可以重复播", day.day.repeats(&"electricbox"))
		_is_false("电话默认只播一次", day.day.repeats(&"caller"))


# ── 报错 ────────────────────────────────────────────────

func _test_errors() -> void:
	_section = "语法报错"

	_error_at("[nope]\nthem: hi\n", 1, "不认识的块")
	_error_at("[story]\nhello\n", 2, "开头没有 them:/me:")
	_error_at("[story]\nthem: hi\n- \"x\" -> X+1\n", 3, "不认识的结局分")
	_error_at("[story]\nthem: hi\n- \"x\" -> nonsense\n", 3, "读不懂的效果")
	_error_at("[mail]\nsubject: x\n", 1, "邮件没写 id")
	_error_at("[mail m1]\nsubject: x\n- \"r\" -> goto=elsewhere\n", 3, "邮件回复不能跳转")
	_error_at("[day]\nnope: 1\n", 2, "[day] 里的野字段")
	_error_at("[account]\npass: x\n", 1, "账户没写用户名")
	_error_at("[mail m1 if=score.Z>=1]\nsubject: x\n", 1, "结局分写错")
	_error_at("[story]\nthem: hi\n- \"x\" if=nonsense -> A+1\n", 3, "选项条件读不懂")
	_error_at("[score]\nA+2\n", 2, "[score] 行少了 if")
	_error_at("[score]\nif day>=1\n", 2, "[score] 行少了箭头")
	_error_at("[story]\n?end\nthem: hi\n", 2, "?end 没有配对的 ?if")
	_error_at("[story]\n?if flag:x\nthem: hi\n", 2, "?if 没有 ?end（报在 ?if 那一行）")
	_error_at("[story]\n?nope\n", 2, "? 开头写错")
	# 整个文件层面的毛病不带行号——指到某一行上只会误导。
	var mixed := story_parser.parse("[story]\nthem: hi\n\n[account a]\npass: x\n", "t.story")
	_is_true("一个文件里混写两类内容要报错", not mixed.ok())
	if not mixed.ok():
		_is_true("混写的报错不带行号", mixed.errors[0].begins_with("t.story: "), mixed.errors[0])

	var empty := story_parser.parse("# 只有注释\n", "t.story")
	_is_true("空文件要报错", not empty.ok())


## 断言：这段文本解析后至少有一条错误，且其中一条落在第 line 行。
func _error_at(text: String, line: int, label: String) -> void:
	var r := story_parser.parse(text, "t.story")
	if r.ok():
		_record(label, false, "本该报错，却过了")
		return
	var wanted := "t.story:%d:" % line
	for e in r.errors:
		if e.begins_with(wanted):
			_record(label, true, "")
			return
	_record(label, false, "错误行号不对，期望 %s，实际 %s" % [wanted, str(r.errors)])


# ── 真文件（走导入器）────────────────────────────────────

func _test_real_files() -> void:
	_section = "真的 .story 文件（导入器产物）"

	var world := load(WORLD_PATH) as world_book
	_is_true("world.story 导入出来是 world_book", world != null)
	if world != null:
		_is_true("有账户", world.accounts.size() >= 1)
		_is_true("五个剧情角色都有档案", world.profiles.size() >= 5)
		_is_true("有电话联系人", world.contacts.size() >= 3)
		_is_true("每个联系人都有通话内容",
			_all_have_calls(world), "有联系人没写 [call]")
		_is_true("有结局判定规则", world.ending_rules.size() >= 1)

		var levels: Array = []
		for p in world.profiles:
			levels.append(p.clearance)
		_is_true("档案分了不同权限等级", _unique(levels).size() >= 2,
			"等级：%s" % str(levels))
		# 主角自己的号是 2 级：查得到 1 级的鲍勃/瑞克，查不到 3、4 级的人。
		for a in world.accounts:
			if String(a.username) == "hrtemp":
				_eq("主角的号是 2 级", a.clearance, 2)
				_is_true("用户名写得进记事本一行", String(a.username).length() <= 6)
				_is_true("密码也写得下", a.password.length() <= 6)

	for i in range(1, 6):
		var day := load("res://story/zh/days/day_%d.story" % i) as day_plan
		_is_true("day_%d.story 导入出来是 day_plan" % i, day != null)
		if day == null:
			continue
		_is_true("day_%d 有开场剧情" % i, day.story != null and not day.story.is_empty())

	var day_1 := load(DAY_1_PATH) as day_plan
	if day_1 == null:
		return
	_eq("第 1 天三封剧情信", day_1.scripted_emails.size(), 3)
	_is_true("Bob 进第 1 天的人事表", &"Bob" in day_1.story_roster)
	_is_true("第 1 天配了电话", day_1.caller != null)
	_is_true("第 1 天有结算规则", day_1.score_rules.size() >= 1)
	for m in day_1.scripted_emails:
		_is_false("第 1 天的信都不算对错（%s）" % m.id, m.graded and m.has_order())

	var day_2 := load("res://story/zh/days/day_2.story") as day_plan
	if day_2 != null:
		var sweeps := 0
		for m in day_2.scripted_emails:
			if m.targets_all_random():
				sweeps += 1
		_eq("第 2 天有一封「全部 fire」的命令", sweeps, 1)
		_is_true("第 2 天的电箱可以重复开", day_2.repeats(&"electricbox"))


## 每个联系人都配了通话内容吗。
func _all_have_calls(world: world_book) -> bool:
	for c in world.contacts:
		if c == null or c.call == null or c.call.is_empty():
			return false
	return true


## 两种语言的内容要**结构一致**：同样的天数、同样的标识、同样的规则。
## 只有给玩家看的字（对话、标题、显示名）才该不一样。
func _test_locales_match() -> void:
	_section = "中英内容对得上"

	var zh := load("res://story/zh/world.story") as world_book
	var en := load("res://story/en/world.story") as world_book
	_is_true("两份 world 都在", zh != null and en != null)
	if zh == null or en == null:
		return

	_eq("账户数一样", en.accounts.size(), zh.accounts.size())
	_eq("档案数一样", en.profiles.size(), zh.profiles.size())
	_eq("联系人数一样", en.contacts.size(), zh.contacts.size())
	_eq("结局规则数一样", en.ending_rules.size(), zh.ending_rules.size())
	_eq("结局文案数一样", en.endings.size(), zh.endings.size())

	_eq("档案的标识一样", _ids(en.profiles, "employee_name"), _ids(zh.profiles, "employee_name"))
	_eq("联系人的标识一样", _ids(en.contacts, "contact_name"), _ids(zh.contacts, "contact_name"))
	for i in range(zh.ending_rules.size()):
		_eq("第 %d 条结局规则的条件一样" % (i + 1),
			en.ending_rules[i].condition, zh.ending_rules[i].condition)

	# 显示名可以不同（本来就该不同），但不能空着。
	for p in en.profiles:
		_is_true("英文档案有显示名：%s" % p.employee_name, not p.label().is_empty())
	for p in zh.profiles:
		_is_true("中文档案有显示名：%s" % p.employee_name, not p.label().is_empty())

	for i in range(1, 6):
		var zh_day := load("res://story/zh/days/day_%d.story" % i) as day_plan
		var en_day := load("res://story/en/days/day_%d.story" % i) as day_plan
		_is_true("第 %d 天两种语言都有" % i, zh_day != null and en_day != null)
		if zh_day == null or en_day == null:
			continue
		_eq("第 %d 天的剧情信数一样" % i, en_day.scripted_emails.size(), zh_day.scripted_emails.size())
		_eq("第 %d 天的填充信数一样" % i, en_day.filler_emails, zh_day.filler_emails)
		_eq("第 %d 天点名的人一样" % i, en_day.story_roster, zh_day.story_roster)
		_eq("第 %d 天的结算规则数一样" % i, en_day.score_rules.size(), zh_day.score_rules.size())
		for j in range(zh_day.scripted_emails.size()):
			_eq("第 %d 天第 %d 封信的 id 一样" % [i, j + 1],
				en_day.scripted_emails[j].id, zh_day.scripted_emails[j].id)
			_eq("第 %d 天第 %d 封信的条件一样" % [i, j + 1],
				en_day.scripted_emails[j].condition, zh_day.scripted_emails[j].condition)


func _ids(items: Array, field: String) -> Array:
	var out: Array = []
	for item in items:
		out.append(item.get(field))
	return out


# ── 断言 ────────────────────────────────────────────────

func _no_errors(r) -> void:
	_record("解析无错误", r.ok(), str(r.errors))


func _unique(a: Array) -> Array:
	var out: Array = []
	for v in a:
		if not (v in out):
			out.append(v)
	return out


func _eq(label: String, actual: Variant, expected: Variant) -> void:
	_record(label, actual == expected, "期望 %s，实际 %s" % [str(expected), str(actual)])


func _is_true(label: String, cond: bool, detail := "") -> void:
	_record(label, cond, "期望为真" if detail.is_empty() else detail)


func _is_false(label: String, cond: bool, detail := "") -> void:
	_record(label, not cond, "期望为假" if detail.is_empty() else detail)


func _record(label: String, ok: bool, detail: String) -> void:
	if ok:
		_passed += 1
		return
	_failed += 1
	_fail_lines.append("  ✗ [%s] %s —— %s" % [_section, label, detail])


func _report() -> void:
	print("\n============ story_script_test ============")
	if _failed == 0:
		print("全部通过：%d 项" % _passed)
	else:
		print("通过 %d 项，失败 %d 项：" % [_passed, _failed])
		for line in _fail_lines:
			print(line)
	print("===========================================\n")
	get_tree().quit(1 if _failed > 0 else 0)
