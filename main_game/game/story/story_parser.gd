extends RefCounted
class_name story_parser

## `.story` 剧本文件的解析器：一段文本 → 一天的内容（day_plan）或全局设定（world_book）。
##
## 剧情不再手点 Inspector，全写在 story/ 下的文本文件里：一天一个文件，
## 一眼能看完这天所有邮件、对话和桥段，能搜、能 diff。导入由
## addons/story_script/ 那个 EditorImportPlugin 负责，**解析这一层不依赖编辑器**，
## 所以测试可以直接喂字符串进来。
##
## 语法（就这些）：
##
##     # 注释
##     [day]                      这一天的参数
##     filler: 4                    随机填充信封数
##     roster: Mira, Jack           强制进人事表的剧情角色
##
##     [story]                    开场剧情
##     them: 对方说的话
##     me:   我说的话
##     them!: 叹号 = 不许提前跳字（can_skip=false）
##     接着写的普通行是上一句的续行
##     - "选项文字" -> B+1, goto=quiet, echo="回显"
##
##     [dialogue quiet]           命名段落，goto 的目标；挂在上一个对话块所属的那段剧情里
##
##     [mail welcome from="Renn" faction=B order=raise:Mira class=2 about=Mira graded=no]
##       （order=fire:*random 表示「当天所有随机员工」；graded=no 表示这封进人事表但不算对错）
##     subject: 标题
##     正文
##     - "回复选项" -> B+1, echo="..."
##
##     [caller] [electricbox] [window]            桌面桥段，写法同 [story]
##                                                （便签没有块：那本是玩家自己写的记事本）
##
## world.story 里则是：
##
##     [contact Mira]          能打电话的人；号码留空 = 每局随机 4 位
##     name: Mira, floor 3
##
##     [call Mira]             拨通之后播的对话，写法同 [story]
##     them: ...
##
##     [account hr_temp]
##     pass: 4471
##     name: Temp HR
##     clearance: 1
##
##     [profile Mira]
##     position: Line supervisor
##     department: Floor 3
##     faction: GROUND
##     clearance: 1
##     档案正文……
##
## 效果（选项 `->` 后面，逗号分隔）：`A+1` / `B-2` / `C+2` / `D+1`（四条结局分）、
## `flag=名字`、`goto=段落id`（只在对话里有效）、`echo="..."`（只在邮件回复里有效）。
##
## 条件（语法见 story_condition）：
##
##     [mail x from="班纳" if=score.A>=2]   整封信只在条件成立时发
##     [mail y from="班纳" if="not score.A>=2"]  条件里有空格就要加引号
##     - "选项" if=level.Bob>=3 -> D+1      条件不成立的选项根本不出现
##     ?if did(promote,Bob,ever)            正文/对话里的一段，成立才显示
##     谢谢您上次的提拔。
##     ?end
##
##     [score]                              日终结算：条件成立就加分
##     if did(fire,*random) -> A+2
##     if "not did(fire,*any)" -> C+2       （条件里有空格就加引号）
##
##     [ending]                             结局判定，按顺序判（写在 world.story 里）
##     if "leading(A) and did(promotion,瑞克,day5)" -> A
##
##     [ending_text A]                      结局卡文案（跟着语言走）
##     title: 瑞克上位
##     正文……
##
##     [names]                              随机员工的名字池
##     王磊, 李娜, 张伟

## 解析结果。day 和 world 只会有一个非空——一个文件要么写一天的内容，
## 要么写全局设定，混着写会报错。
class Result:
	extends RefCounted
	var day: day_plan = null
	var world: world_book = null
	var errors: Array[String] = []

	func ok() -> bool:
		return errors.is_empty()


const DAY_BLOCKS := ["day", "score", "story", "dialogue", "mail", "caller", "electricbox", "window"]
const WORLD_BLOCKS := ["account", "profile", "contact", "call", "ending", "ending_text", "names"]

## 桥段块 -> day_plan 上的哪个槽。
## 便签不在这里：桌上那本是玩家自己写字的记事本（notes_page），不播对话。
const EVENT_SLOTS := {
	"caller": "caller",
	"electricbox": "electricbox",
	"window": "window",
}

const ORDER_NAMES := {
	"fire": email_def.Order.FIRE,
	"raise": email_def.Order.RAISE,
	"promotion": email_def.Order.PROMOTION,
	"reduction": email_def.Order.REDUCTION,
}

const FACTION_NAMES := {
	"a": faction.Id.A,
	"b": faction.Id.B,
	"ground": faction.Id.GROUND,
	"none": faction.Id.NONE,
}


var _source := "story"
var _result: Result

# 当前块的状态
var _block := ""
var _line_no := 0

var _day: day_plan
var _world: world_book

## 当前在写哪一段对话（[story] / 各桥段），[dialogue x] 会挂进同一段剧情。
var _conversation: conversation = null
var _dialogue: dialogue = null
var _bubble: conversation_bubble = null

var _mail: email_def = null
var _account: account = null
var _profile: employee_profile = null
var _contact: contact = null
var _ending: ending_def = null

## `?if ... ?end` 的嵌套栈，栈顶就是当前这几行的条件。
var _cond_stack: Array = []

## 邮件正文按条件分段攒着：[{cond, lines}]，块结束时变成 body_blocks。
var _blocks: Array = []

## 正文（档案）攒到这里，块结束时一次性写进去。
var _body: PackedStringArray = []
## 已经开始写正文了：之后再出现 `key: value` 也当正文，
## 不然邮件里写一句 "Floor 3: adjustments" 会被误当成头部字段。
var _body_started := false


## 解析一段剧本。source 只用来拼报错信息（通常传文件名）。
static func parse(text: String, source := "story") -> Result:
	var p := story_parser.new()
	return p._run(text, source)


func _run(text: String, source: String) -> Result:
	_source = source
	_result = Result.new()
	_day = day_plan.new()
	_world = world_book.new()

	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	for i in range(lines.size()):
		_line_no = i + 1
		_handle_line(String(lines[i]))
	_close_block()

	var has_day := _saw_day
	var has_world := _saw_world
	if has_day and has_world:
		_file_error("同一个文件里不能既写某一天的内容、又写全局设定（account / profile）")
	elif has_day:
		_result.day = _day
	elif has_world:
		_result.world = _world
	else:
		_file_error("文件里没有任何块，至少要有一个 [story] / [mail] / [account] / [profile]")

	return _result


var _saw_day := false
var _saw_world := false


func _handle_line(raw: String) -> void:
	var line := raw.strip_edges()
	if line.begins_with("#"):
		return

	if line.begins_with("[") and line.ends_with("]"):
		_close_block()
		_open_block(line.substr(1, line.length() - 2).strip_edges())
		return

	if line.is_empty():
		# 空行只在正文里有意义（分段），别的地方就是排版。
		if _body_started:
			if _block == "mail":
				_block_line("")
			else:
				_body.append("")
		_bubble = null    # 空行断开续行
		return

	if _block.is_empty():
		_error("这一行不在任何块里：%s" % line)
		return

	if line.begins_with("?"):
		_condition_line(line)
		return

	if line.begins_with("- "):
		_choice_line(line.substr(2).strip_edges())
		return

	match _block:
		"day":
			_day_field(line)
		"score":
			_score_line(line)
		"story", "dialogue", "caller", "electricbox", "window":
			_dialogue_line(line)
		"mail":
			_mail_line(line)
		"account":
			_account_line(line)
		"profile":
			_profile_line(line)
		"contact":
			_contact_line(line)
		"call":
			_dialogue_line(line)
		"ending":
			_ending_line(line)
		"ending_text":
			_ending_text_line(line)
		"names":
			_names_line(line)


# ── 开块 / 收块 ─────────────────────────────────────────

func _open_block(header: String) -> void:
	var parts := _split_header(header)
	if parts.is_empty():
		_error("空的块头 []")
		return

	var kind := String(parts[0]).to_lower()
	_block = kind
	_body = PackedStringArray()
	_body_started = false
	_bubble = null

	if kind in DAY_BLOCKS:
		_saw_day = true
	elif kind in WORLD_BLOCKS:
		_saw_world = true
	else:
		_error("不认识的块 [%s]" % kind)
		_block = ""
		return

	match kind:
		"day", "score", "ending", "names":
			pass
		"ending_text":
			_ending = ending_def.new()
			_ending.ending_id = StringName(String(parts[1]).to_upper()) if parts.size() > 1 else &""
			if not (String(_ending.ending_id) in ["A", "B", "C", "D", "E"]):
				_error("[ending_text] 要写成 [ending_text A]（A/B/C/D/E）")
		"story":
			_conversation = conversation.new()
			_day.story = _conversation
			_dialogue = _new_dialogue(&"start")
		"dialogue":
			if _conversation == null:
				_error("[dialogue] 前面得先有 [story] 或某个桥段块")
				_block = ""
				return
			var id := StringName(parts[1]) if parts.size() > 1 else &""
			if String(id).is_empty():
				_error("[dialogue] 要有名字，比如 [dialogue quiet]")
				id = &"unnamed"
			_dialogue = _new_dialogue(id)
		"mail":
			_mail = email_def.new()
			_mail.id = StringName(parts[1]) if parts.size() > 1 else &""
			if String(_mail.id).is_empty():
				_error("[mail] 要有 id，比如 [mail welcome ...]")
			_mail_header(parts.slice(2) if parts.size() > 2 else [], header)
		"caller", "electricbox", "window":
			_conversation = conversation.new()
			_day.set(EVENT_SLOTS[kind], _conversation)
			if _header_flag(parts, "repeat"):
				_day.repeatable_events.append(StringName(kind))
			_dialogue = _new_dialogue(&"start")
		"contact":
			_contact = contact.new()
			_contact.contact_name = StringName(parts[1]) if parts.size() > 1 else &""
			if String(_contact.contact_name).is_empty():
				_error("[contact] 要有名字，比如 [contact Mira]")
		"call":
			# 对话挂到同名的 [contact] 上，所以 [contact] 必须写在前面。
			var who := StringName(parts[1]) if parts.size() > 1 else &""
			var target := _find_contact(who)
			if target == null:
				_error("[call %s] 找不到同名的 [contact]（要先写 [contact %s]）" % [who, who])
				_block = ""
				return
			_conversation = conversation.new()
			target.call = _conversation
			_dialogue = _new_dialogue(&"start")
		"account":
			_account = account.new()
			_account.username = StringName(parts[1]) if parts.size() > 1 else &""
			if String(_account.username).is_empty():
				_error("[account] 要有用户名，比如 [account hr_temp]")
		"profile":
			_profile = employee_profile.new()
			_profile.employee_name = StringName(parts[1]) if parts.size() > 1 else &""
			if String(_profile.employee_name).is_empty():
				_error("[profile] 要有员工名，比如 [profile Mira]")


func _close_block() -> void:
	match _block:
		"mail":
			if _mail != null:
				_mail.body_blocks = _take_blocks()
				_day.scripted_emails.append(_mail)
			_mail = null
		"account":
			if _account != null:
				_world.accounts.append(_account)
			_account = null
		"profile":
			if _profile != null:
				_profile.body = _body_text()
				_world.profiles.append(_profile)
			_profile = null
		"contact":
			if _contact != null:
				_world.contacts.append(_contact)
			_contact = null
		"ending_text":
			if _ending != null:
				_ending.body = _body_text()
				_world.endings.append(_ending)
			_ending = null
	if not _cond_stack.is_empty():
		var opened: int = _line_no
		for entry in _cond_stack:
			opened = mini(opened, int(entry["line"]))
		_result.errors.append("%s:%d: 这个 ?if 没有配对的 ?end" % [_source, opened])
	_cond_stack.clear()
	_block = ""
	_blocks = []
	_body = PackedStringArray()
	_body_started = false
	_bubble = null


func _new_dialogue(id: StringName) -> dialogue:
	var d := dialogue.new()
	d.id = id
	_conversation.dialogues.append(d)
	return d


## 当前这几行归哪个条件管（`?if` 嵌套时按 and 串起来）。
func _current_condition() -> String:
	var parts := PackedStringArray()
	for entry in _cond_stack:
		parts.append(String(entry["cond"]))
	return " and ".join(parts)


## `?if <条件>` / `?end`
func _condition_line(line: String) -> void:
	var body := line.substr(1).strip_edges()
	if body.to_lower() == "end":
		if _cond_stack.is_empty():
			_error("?end 前面没有 ?if")
		else:
			_cond_stack.pop_back()
		_bubble = null      # 条件段之间不许续行，免得跨段接歪
		return
	if body.to_lower().begins_with("if "):
		# 引号可写可不写：?if 后面整行都是条件，不会被空格切开。
		var cond := _unquote(body.substr(3).strip_edges())
		var problem := story_condition.validate(cond)
		if not problem.is_empty():
			_error(problem)
		# 记下行号：没配对的 ?end 要报在 ?if 那一行，不能报在文件末尾。
		_cond_stack.append({"cond": cond, "line": _line_no})
		_bubble = null
		return
	_error("? 开头的行只能是 ?if <条件> 或 ?end：%s" % line)


## 往邮件正文里加一行，跟着当前条件走。
func _block_line(line: String) -> void:
	var cond := _current_condition()
	if _blocks.is_empty() or String(_blocks[-1]["cond"]) != cond:
		# lines 用普通 Array 而不是 PackedStringArray：Packed 是值类型，
		# `_blocks[-1]["lines"].append(...)` 会往一份拷贝里加，行全丢了。
		_blocks.append({"cond": cond, "lines": []})
	_blocks[-1]["lines"].append(line)


## 收尾：把攒的分段变成 story_text_block，顺手去掉首尾空行。
func _take_blocks() -> Array[story_text_block]:
	var out: Array[story_text_block] = []
	for raw in _blocks:
		var lines: Array = raw["lines"]
		while not lines.is_empty() and String(lines[0]).is_empty():
			lines.pop_front()
		while not lines.is_empty() and String(lines[-1]).is_empty():
			lines.pop_back()
		if lines.is_empty():
			continue
		var block := story_text_block.new()
		block.condition = String(raw["cond"])
		block.text = "\n".join(PackedStringArray(lines))
		out.append(block)
	return out


## 正文：去掉首尾空行，中间的空行保留成段落间隔。
func _body_text() -> String:
	var lines := Array(_body)
	while not lines.is_empty() and String(lines[0]).is_empty():
		lines.pop_front()
	while not lines.is_empty() and String(lines[-1]).is_empty():
		lines.pop_back()
	return "\n".join(PackedStringArray(lines))


# ── 各种行 ──────────────────────────────────────────────

func _day_field(line: String) -> void:
	var kv := _split_kv(line)
	if kv.is_empty():
		_error("[day] 里只能写 filler: / roster: / filler_exclude:，读不懂这一行：%s" % line)
		return
	match kv[0]:
		"filler_exclude":
			for name in kv[1].split(",", false):
				var action := _order_name(String(name).strip_edges())
				if action.is_empty():
					_error("filler_exclude 只能写 fire/raise/promotion/reduction：%s" % name)
				else:
					_day.filler_exclude.append(StringName(action))
		"filler":
			if not kv[1].is_valid_int():
				_error("filler 要是整数：%s" % kv[1])
				return
			_day.filler_emails = int(kv[1])
		"roster":
			for name in kv[1].split(",", false):
				var n := String(name).strip_edges()
				if not n.is_empty():
					_day.story_roster.append(StringName(n))
		_:
			_error("[day] 里不认识的字段：%s" % kv[0])


func _dialogue_line(line: String) -> void:
	var side := -1
	var can_skip := true
	var text := ""

	for prefix in [["them:", conversation_bubble.Side.THEIRS, true],
			["them!:", conversation_bubble.Side.THEIRS, false],
			["me:", conversation_bubble.Side.MINE, true],
			["me!:", conversation_bubble.Side.MINE, false]]:
		var p: String = prefix[0]
		if line.to_lower().begins_with(p):
			side = prefix[1]
			can_skip = prefix[2]
			text = line.substr(p.length()).strip_edges()
			break

	if side < 0:
		# 没有前缀 = 上一句的续行。
		if _bubble == null:
			_error("对话行要以 them: 或 me: 开头：%s" % line)
			return
		_bubble.text += "\n" + line
		return

	var b := conversation_bubble.new()
	b.side = side
	b.can_skip = can_skip
	b.text = text
	b.condition = _current_condition()
	_dialogue.bubbles.append(b)
	_bubble = b


func _mail_line(line: String) -> void:
	var kv := _split_kv(line)
	if not _body_started and not kv.is_empty() and kv[0] == "subject":
		_mail.subject = kv[1]
		return
	_body_started = true
	_block_line(line)


## [ending] 里的一行：`if <条件> -> A`（走哪个结局）。
## 按写的顺序判，第一条成立的算数。
func _ending_line(line: String) -> void:
	if not line.to_lower().begins_with("if "):
		_error("[ending] 里每行都要写成 if <条件> -> A：%s" % line)
		return
	var arrow := line.find("->")
	if arrow < 0:
		_error("[ending] 这一行少了 ->：%s" % line)
		return

	var cond := _unquote(line.substr(3, arrow - 3).strip_edges())
	var problem := story_condition.validate(cond)
	if not problem.is_empty():
		_error(problem)

	var target := line.substr(arrow + 2).strip_edges().to_upper()
	if not (target in ["A", "B", "C", "D", "E"]):
		_error("[ending] 的结局只能是 A/B/C/D/E：%s" % target)
		return

	var rule := ending_rule.new()
	rule.condition = cond
	rule.ending = StringName(target)
	_world.ending_rules.append(rule)


## [score] 里的一行：`if <条件> -> <效果>`
func _score_line(line: String) -> void:
	if not line.to_lower().begins_with("if "):
		_error("[score] 里每行都要写成 if <条件> -> A+2：%s" % line)
		return
	var arrow := line.find("->")
	if arrow < 0:
		_error("[score] 这一行少了 ->：%s" % line)
		return

	var cond := _unquote(line.substr(3, arrow - 3).strip_edges())
	var problem := story_condition.validate(cond)
	if not problem.is_empty():
		_error(problem)

	var parsed := _parse_effects(line.substr(arrow + 2).strip_edges())
	if not String(parsed["goto"]).is_empty() or not String(parsed["echo"]).is_empty():
		_error("[score] 里只能加分和打 flag，goto / echo 用不上")

	var rule := score_rule.new()
	rule.condition = cond
	rule.effect = parsed["effect"]
	_day.score_rules.append(rule)


## [ending_text X] 里的字段：`title:` 一行，其余是正文。
func _ending_text_line(line: String) -> void:
	var kv := _split_kv(line)
	if not _body_started and not kv.is_empty() and kv[0] == "title":
		_ending.title = kv[1]
		return
	_body_started = true
	_body.append(line)


## [names] 块：随机员工的名字池，一行一个或逗号分隔。
func _names_line(line: String) -> void:
	for name in line.split(",", false):
		var n := String(name).strip_edges()
		if not n.is_empty():
			_world.random_names.append(StringName(n))


## [contact] 里的字段。
func _contact_line(line: String) -> void:
	var kv := _split_kv(line)
	if kv.is_empty():
		_error("[contact] 里只能写 name: / number:，读不懂：%s" % line)
		return
	match kv[0]:
		"name":
			_contact.display_name = kv[1]
		"number":
			_contact.fixed_number = kv[1]
		_:
			_error("[contact] 里不认识的字段：%s" % kv[0])


## 按名字找已经写过的联系人。
func _find_contact(contact_name: StringName) -> contact:
	for c in _world.contacts:
		if c != null and c.contact_name == contact_name:
			return c
	# 当前正在写的那个还没进 _world.contacts。
	if _contact != null and _contact.contact_name == contact_name:
		return _contact
	return null


## 块头里的开关参数（`repeat=yes`）。
func _header_flag(parts: Array, key: String) -> bool:
	for token in parts:
		var t := String(token)
		var eq := t.find("=")
		if eq <= 0:
			continue
		if t.substr(0, eq).strip_edges().to_lower() != key:
			continue
		return not (_unquote(t.substr(eq + 1).strip_edges()).to_lower() in ["no", "false", "0"])
	return false


func _account_line(line: String) -> void:
	var kv := _split_kv(line)
	if kv.is_empty():
		_error("[account] 里只能写 pass: / name: / clearance:，读不懂：%s" % line)
		return
	match kv[0]:
		"pass":
			_account.password = kv[1]
		"name":
			_account.display_name = kv[1]
		"clearance":
			if not kv[1].is_valid_int():
				_error("clearance 要是整数：%s" % kv[1])
				return
			_account.clearance = int(kv[1])
		_:
			_error("[account] 里不认识的字段：%s" % kv[0])


func _profile_line(line: String) -> void:
	var kv := _split_kv(line)
	if not _body_started and not kv.is_empty() and kv[0] in ["name", "position", "department", "faction", "clearance"]:
		match kv[0]:
			"name":
				_profile.display_name = kv[1]
			"position":
				_profile.position = kv[1]
			"department":
				_profile.department = kv[1]
			"faction":
				_profile.employee_faction = _parse_faction(kv[1])
			"clearance":
				if not kv[1].is_valid_int():
					_error("clearance 要是整数：%s" % kv[1])
				else:
					_profile.clearance = int(kv[1])
		return
	_body_started = true
	_body.append(line)


## 选项行：- "按钮文字" -> 效果, 效果
func _choice_line(line: String) -> void:
	var text := ""
	var rest := ""
	var arrow := line.find("->")
	var head: String = (line.substr(0, arrow) if arrow >= 0 else line).strip_edges()
	if arrow >= 0:
		rest = line.substr(arrow + 2).strip_edges()

	# 选项自己的条件写在文字后面：- "文字" if=level.Bob>=3 -> D+1
	var own_condition := ""
	var if_at := head.rfind(" if=")
	if if_at > 0:
		own_condition = _unquote(head.substr(if_at + 4).strip_edges())
		head = head.substr(0, if_at).strip_edges()
		var problem := story_condition.validate(own_condition)
		if not problem.is_empty():
			_error(problem)

	if head.begins_with("\"") and head.ends_with("\"") and head.length() >= 2:
		text = head.substr(1, head.length() - 2)
	else:
		text = head
	if text.is_empty():
		_error("选项要有文字：%s" % line)
		return

	var parsed := _parse_effects(rest)
	var effect: story_effect = parsed["effect"]
	var goto: StringName = parsed["goto"]
	var echo: String = parsed["echo"]

	match _block:
		"mail":
			if not String(goto).is_empty():
				_error("邮件回复不能写 goto（邮件没有段落可跳）")
			if not own_condition.is_empty():
				_error("邮件回复不能带 if=（整封信的条件写在 [mail] 那一行）")
			var r := email_reply.new()
			r.text = text
			if not echo.is_empty():
				effect.reply_echo = echo
			r.effect = effect
			_mail.replies.append(r)
		"story", "dialogue", "caller", "electricbox", "window", "call":
			if not echo.is_empty():
				_error("echo 只有邮件回复用得上")
			if _bubble == null:
				_error("选项要挂在一句对话下面")
				return
			var c := conversation_choice.new()
			c.text = text
			c.goto = goto
			c.effect = effect
			c.condition = _current_condition() if own_condition.is_empty() else own_condition
			_bubble.choices.append(c)
		_:
			_error("[%s] 块里不能写选项" % _block)


## 返回 {"effect": story_effect, "goto": StringName, "echo": String}
func _parse_effects(text: String) -> Dictionary:
	var effect := story_effect.new()
	var out := {"effect": effect, "goto": &"", "echo": ""}
	for token in _split_top_level(text, ","):
		# _split_top_level 返回无类型 Array，元素推不出 String，得显式转。
		var t := String(token).strip_edges()
		if t.is_empty():
			continue

		var eq := t.find("=")
		if eq > 0:
			var key := t.substr(0, eq).strip_edges().to_lower()
			var value := _unquote(t.substr(eq + 1).strip_edges())
			match key:
				"flag":
					effect.set_flags.append(StringName(value))
				"goto":
					out["goto"] = StringName(value)
				"echo":
					out["echo"] = value
				_:
					_error("不认识的效果 \"%s\"" % t)
			continue

		# A+1 / B-2 / GROUND+1
		var sign_at := maxi(t.find("+"), t.find("-"))
		if sign_at <= 0 or not t.substr(sign_at + 1).is_valid_int():
			_error("不认识的效果 \"%s\"（立场要写成 A+1 / GROUND-2 这样）" % t)
			continue
		var amount := int(t.substr(sign_at + 1))
		if t[sign_at] == "-":
			amount = -amount
		match t.substr(0, sign_at).strip_edges().to_upper():
			"A":
				effect.a_delta += amount
			"B":
				effect.b_delta += amount
			"C":
				effect.c_delta += amount
			"D":
				effect.d_delta += amount
			_:
				_error("不认识的结局分 \"%s\"（只有 A / B / C / D）" % t.substr(0, sign_at))
	return out


func _mail_header(params: Array, header := "") -> void:
	for token in params:
		var t := String(token)
		var eq := t.find("=")
		if eq <= 0:
			_error("[mail] 的参数要写成 key=value：%s" % t)
			continue
		var key := t.substr(0, eq).strip_edges().to_lower()
		var value := _unquote(t.substr(eq + 1).strip_edges())
		match key:
			"from":
				_mail.sender_name = value
			"faction":
				_mail.sender_faction = _parse_faction(value)
			"class":
				if not value.is_valid_int():
					_error("class 要是 0-4 的整数：%s" % value)
				else:
					_mail.sender_class = clampi(int(value), 0, 4)
			"about":
				_mail.about_employee = StringName(value)
			"graded":
				_mail.graded = not (value.to_lower() in ["no", "false", "0"])
			"if":
				var problem := story_condition.validate(value)
				if not problem.is_empty():
					_error(problem)
				_mail.condition = value
			"order":
				var bits := value.split(":", false)
				if bits.size() != 2 or not ORDER_NAMES.has(String(bits[0]).to_lower()):
					_error("order 要写成 order=raise:Mira（动作有 fire/raise/promotion/reduction）：%s" % value)
					continue
				_mail.order = ORDER_NAMES[String(bits[0]).to_lower()]
				# *random = 当天所有随机员工，round_manager 展开成一人一条。
				_mail.target_employee = StringName(String(bits[1]).strip_edges())
			_:
				# 条件里有空格（not / and）却没加引号时，会被空格切成两截，
				# 报错落在半截条件上很难懂，这里直接把正确写法给出来。
				if header.contains("if="):
					_error("[mail] 里不认识的参数 \"%s\"——条件里有空格要加引号，写成 if=\"not score.A>=1\"" % key)
				else:
					_error("[mail] 里不认识的参数 \"%s\"" % key)


## 动作名转成 f_instruction 用的字面量，不认识返回空串。
func _order_name(value: String) -> String:
	var key := value.strip_edges().to_lower()
	if ORDER_NAMES.has(key):
		return email_def.ORDER_NAMES[ORDER_NAMES[key]]
	return ""


func _parse_faction(value: String) -> int:
	var key := value.strip_edges().to_lower()
	if FACTION_NAMES.has(key):
		return FACTION_NAMES[key]
	_error("不认识的派系 \"%s\"（只有 A / B / GROUND / NONE）" % value)
	return faction.Id.NONE


# ── 小工具 ──────────────────────────────────────────────

## 块头按空格切，但引号里的空格不算：[mail x from="Renn, Ops" faction=B]
func _split_header(header: String) -> Array:
	return _split_top_level(header, " ")


## 按分隔符切，引号里的分隔符不算。
func _split_top_level(text: String, sep: String) -> Array:
	var out: Array = []
	var current := ""
	var in_quotes := false
	for i in range(text.length()):
		var ch := text[i]
		if ch == "\"":
			in_quotes = not in_quotes
			current += ch
			continue
		if ch == sep and not in_quotes:
			if not current.strip_edges().is_empty():
				out.append(current.strip_edges())
			current = ""
			continue
		current += ch
	if not current.strip_edges().is_empty():
		out.append(current.strip_edges())
	return out


## `key: value` → ["key", "value"]，不是这个形状就返回空数组。
func _split_kv(line: String) -> Array:
	var colon := line.find(":")
	if colon <= 0:
		return []
	var key := line.substr(0, colon).strip_edges().to_lower()
	if key.is_empty() or key.contains(" "):
		return []
	return [key, line.substr(colon + 1).strip_edges()]


func _unquote(text: String) -> String:
	if text.length() >= 2 and text.begins_with("\"") and text.ends_with("\""):
		return text.substr(1, text.length() - 2)
	return text


func _error(message: String) -> void:
	_result.errors.append("%s:%d: %s" % [_source, _line_no, message])


## 整个文件层面的毛病（不属于某一行），不带行号，免得指到一个无辜的行上。
func _file_error(message: String) -> void:
	_result.errors.append("%s: %s" % [_source, message])
