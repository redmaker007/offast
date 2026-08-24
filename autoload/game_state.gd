extends Node

## 剧情状态（autoload GameState）：结局分、员工权限、剧情开关、登录状态、人事调动日志。
##
## round_manager 管的是「这一天怎么走」，这里管的是「这一局玩家是个什么人」——
## 五天下来这些数值决定结局。两边故意分开：玩法（扣命、判分）不该被结局分影响，
## 结局分也不该跟着天数流转被清掉。
##
## 结局分谁都可以往这里写，但**只通过 apply_effect() 写**——邮件回复、对话选项、
## 桥段选项、日终结算规则都是同一个 story_effect 类型，规则只有一套。

## 四条结局线。E（被开除）不在这里——那是三条命掉光的结果，不靠攒分。
const SCORE_A := &"A"
const SCORE_B := &"B"
const SCORE_C := &"C"
const SCORE_D := &"D"
const KEYS: Array[StringName] = [SCORE_A, SCORE_B, SCORE_C, SCORE_D]

## 主角自己在人事表里那一行的名字。给自己批 promotion 是结局 B 的触发条件，
## 所以他也得能出现在表上。
const SELF := &"me"

var save_id := "game_state"

## 四条结局分。键是 "A"/"B"/"C"/"D" 字符串而不是枚举——枚举是 int，
## 改顺序会把旧存档里的分数全对错位。
var scores: Dictionary = {}

## 每个员工**当前**的权限等级。初值来自 world.story 里档案上的 clearance，
## 之后每被批一次 promotion 就 +1。
##
## 这是整条 D 线的地基：鲍勃要连升三次到 4 级，才拿得到保洁的号码、
## 才够资格联署人事处分。查不到的人返回 -1（不存在的人没有权限）。
var levels: Dictionary = {}

## 剧情开关。隐藏结局的条件、桥段「今天已经触发过」都记在这里。
var flags: Dictionary = {}

## 当前登录的账户名，空串 = 没登录。**一直登着**，除非玩家自己 Sign out。
var current_account: StringName = &""

## 当前账户的权限等级。存下来而不是每次回头查 story_book：
## 读档时不需要先把内容表准备好，权限就已经是对的。
var account_clearance: int = 0

## 哪一天登的。**只是留个记录**，不再拿来判「今天还算不算登着」——
## 电脑不会每天早上自动锁上（用户拍板：只有第 1 天要敲密码）。
var login_day: int = 0

## 人事调动日志，一天一批，第 5 天结局前整个摊给玩家看。
## 每条：{day, employee, actions:Array, issuer:StringName, complied:bool}
var personnel_log: Array = []

## 已经回复过的邮件 id。读档回来重复回复不会再加一次分。
var answered_emails: Array = []

## 今天是第几天。条件里写 `day>=4`、`did(...)` 默认「只看今天」都要用它。
## round_manager 每天开工时写一次。
var day: int = 0

## 打通过谁的电话（条件 `called(米拉)` 查这个）。
var called: Array = []

## 每个联系人这一局的电话号码。**每局重新随机**，防止玩家背号码；
## 文案里写 `{caller:米拉}`，显示前由 story_text 换成真号码。
var caller_numbers: Dictionary = {}

## 每个账户这一局的密码。和电话号码同一个理由：**每局重新随机**，
## 防止玩家背密码。内容文件里写死了 `pass:` 的就用写死的那个。
var account_passwords: Dictionary = {}


func _ready() -> void:
	add_to_group(SaveState.GROUP)
	reset()


## 开新局时清空。菜单点 New Start 会走到这里（round_manager.start_game）。
func reset() -> void:
	scores = {}
	for k in KEYS:
		scores[k] = 0
	levels = {}
	day = 0
	called = []
	caller_numbers = {}
	account_passwords = {}
	flags = {}
	current_account = &""
	account_clearance = 0
	login_day = 0
	personnel_log = []
	answered_emails = []
	SignalBus.scores_changed.emit(scores.duplicate())


# ── 写入 ────────────────────────────────────────────────

## 唯一的写入口。传 null 或空 effect 是安全的空操作。
func apply_effect(e: story_effect) -> void:
	if e == null:
		return
	add_score(SCORE_A, e.a_delta)
	add_score(SCORE_B, e.b_delta)
	add_score(SCORE_C, e.c_delta)
	add_score(SCORE_D, e.d_delta)
	for f in e.set_flags:
		set_flag(f)
	SignalBus.scores_changed.emit(scores.duplicate())


func add_score(key: StringName, amount: int) -> void:
	if amount == 0 or not scores.has(key):
		return
	scores[key] = int(scores[key]) + amount
	SignalBus.scores_changed.emit(scores.duplicate())


func score_of(key: StringName) -> int:
	return int(scores.get(key, 0))


# ── 员工权限 ────────────────────────────────────────────

## 开局把档案上写的 clearance 灌进来（round_manager.start_game 调）。
## 已经有值的不覆盖——读档回来的等级是玩家挣出来的，不能被初值冲掉。
func seed_levels(book: world_book) -> void:
	if book == null:
		return
	for p in book.profiles:
		if p != null and not levels.has(p.employee_name):
			levels[p.employee_name] = p.clearance


## 某人现在几级。没有档案的人（随机员工）返回 -1。
func level_of(employee_name: StringName) -> int:
	return int(levels.get(employee_name, -1))


## 批了一次 promotion：权限 +1。没档案的人不记——随机员工升不升级没人关心。
func promote(employee_name: StringName) -> void:
	if not levels.has(employee_name):
		return
	levels[employee_name] = int(levels[employee_name]) + 1
	SignalBus.level_changed.emit(employee_name, int(levels[employee_name]))


func set_flag(f: StringName, on := true) -> void:
	if String(f).is_empty():
		return
	flags[f] = on


func has_flag(f: StringName) -> bool:
	return bool(flags.get(f, false))


# ── 登录 ────────────────────────────────────────────────

## 登录成功。哪一天登的顺手记一笔（只是记录，不影响判定）。
func login(signed_in: account, day: int) -> void:
	if signed_in == null:
		return
	current_account = signed_in.username
	account_clearance = signed_in.clearance
	login_day = day
	SignalBus.login_succeeded.emit(signed_in)


## 退出登录。**只有玩家自己按 Sign out 才会走到这里**——
## 开新的一天不再自动登出，昨天登着的号今天照样能用。
func logout() -> void:
	if String(current_account).is_empty():
		return
	current_account = &""
	account_clearance = 0
	login_day = 0
	SignalBus.logged_out.emit()


## 现在是不是登着的。**跨天有效**：登过一次就一直登着，直到玩家自己 Sign out
## （或者开新局）。所以密码只有第 1 天真的要敲一遍。
func is_logged_in() -> bool:
	return not String(current_account).is_empty()


## 当前权限。没登录就是 -1（比任何档案的 clearance 都低，什么都查不到）。
func clearance() -> int:
	return account_clearance if not String(current_account).is_empty() else -1


func mark_email_answered(id: StringName) -> void:
	if not String(id).is_empty() and not answered_emails.has(id):
		answered_emails.append(id)


func is_email_answered(id: StringName) -> bool:
	return answered_emails.has(id)


# ── 电话 ────────────────────────────────────────────────

## 开局给每个联系人分配号码：写死了的用写死的，没写的随机 4 位（互不重复）。
##
## **每局重新随机**是设计要求（防止玩家背号码），所以号码进存档、
## 但不跨局；4 位是因为记事本一行只写得下 6 个字符。
func seed_caller_numbers(book: world_book) -> void:
	if book == null:
		return
	var used: Array = []
	for c in book.contacts:
		if c != null and not c.fixed_number.is_empty():
			used.append(c.fixed_number)
	for c in book.contacts:
		if c == null or caller_numbers.has(c.contact_name):
			continue
		if not c.fixed_number.is_empty():
			caller_numbers[c.contact_name] = c.fixed_number
			continue
		var number := ""
		# 1000-9999 有 9000 个，联系人只有几个，撞号重摇几次就够。
		for attempt in range(64):
			number = str(randi_range(1000, 9999))
			if not used.has(number):
				break
		used.append(number)
		caller_numbers[c.contact_name] = number


## 某人这一局的号码，没有就是空串。
func caller_number(contact_name: StringName) -> String:
	return str(caller_numbers.get(contact_name, ""))


## 开局给每个账户定这一局的密码：内容里写死了 `pass:` 的用写死的，
## 留空的随机摇 4 位（互不重复）。
##
## **每局重新随机**是设计要求——密码抄在记事本上，背下来就没意义了。
## 4 位是因为记事本一行只写得下 6 个字符（见 notes_page）。
func seed_account_passwords(book: world_book) -> void:
	if book == null:
		return
	var used: Array = []
	for a in book.accounts:
		if a != null and not a.fixed_password.is_empty():
			used.append(a.fixed_password)
	for a in book.accounts:
		if a == null or account_passwords.has(a.username):
			continue
		if not a.fixed_password.is_empty():
			account_passwords[a.username] = a.fixed_password
			continue
		var secret := ""
		for attempt in range(64):
			secret = str(randi_range(1000, 9999))
			if not used.has(secret):
				break
		used.append(secret)
		account_passwords[a.username] = secret


## 某个账户这一局的密码，没有就是空串（空串谁都登不进去）。
func account_password(username: StringName) -> String:
	return str(account_passwords.get(username, ""))


func mark_called(contact_name: StringName) -> void:
	if not String(contact_name).is_empty() and not called.has(contact_name):
		called.append(contact_name)


func has_called(contact_name: StringName) -> bool:
	return called.has(contact_name)


# ── 「你到底做过什么」──────────────────────────────────

## 某天（0 = 任意一天）有没有对某人做过某个动作。查的是人事日志，
## 也就是**日终真正生效的那张表**，不是玩家中途勾了又取消的过程。
func did(action: String, employee_name: StringName, on_day := 0) -> bool:
	for row in personnel_log:
		if on_day > 0 and int(row.get("day", 0)) != on_day:
			continue
		if str(row.get("employee", "")) != String(employee_name):
			continue
		if bool(row.get("actual", {}).get(action, false)):
			return true
	return false


## 那天有没有对**任何人**做过这个动作。「一个员工都没有 fire」就是 not did_any。
func did_any(action: String, on_day := 0) -> bool:
	for row in personnel_log:
		if on_day > 0 and int(row.get("day", 0)) != on_day:
			continue
		if bool(row.get("actual", {}).get(action, false)):
			return true
	return false


## 那天**所有随机员工**是不是都被做了这个动作（第二天班纳那条命令的判定）。
## 一个随机员工都没有的话返回 false——空集不算「全做了」。
func did_all_random(action: String, on_day := 0) -> bool:
	var seen := false
	for row in personnel_log:
		if on_day > 0 and int(row.get("day", 0)) != on_day:
			continue
		if not bool(row.get("random", false)):
			continue
		seen = true
		if not bool(row.get("actual", {}).get(action, false)):
			return false
	return seen


## 日终由 round_manager 调，一天一批。
func log_personnel(day: int, entry: Dictionary) -> void:
	var row := entry.duplicate()
	row["day"] = day
	personnel_log.append(row)


## 现在哪条结局线领先。**并列时固定按 C > D > B > A 取**——
## 谁都不帮（C）是最保守的解释，两派并列时不该白送给任何一派。
## 顺序写死是为了确定性：同一个存档永远出同样的结局。
func leading() -> StringName:
	var best_key := SCORE_C
	var best := score_of(SCORE_C)
	for k in [SCORE_D, SCORE_B, SCORE_A]:
		if score_of(k) > best:
			best = score_of(k)
			best_key = k
	return best_key


## 两条线打平不打平。第五天 A/B 持平时两个头目会各发一封信逼你二选一。
func tied(a: StringName, b: StringName) -> bool:
	return score_of(a) == score_of(b)


# ── 存档 ────────────────────────────────────────────────

func save_data() -> Dictionary:
	return {
		"scores": scores,
		"levels": levels,
		"flags": flags,
		"current_account": current_account,
		"account_clearance": account_clearance,
		"login_day": login_day,
		"personnel_log": personnel_log,
		"answered_emails": answered_emails,
		"day": day,
		"called": called,
		"caller_numbers": caller_numbers,
		"account_passwords": account_passwords,
	}


func load_data(d: Dictionary) -> void:
	scores = d.get("scores", {})
	for k in KEYS:
		if not scores.has(k):
			scores[k] = 0
	levels = d.get("levels", {})
	flags = d.get("flags", {})
	current_account = d.get("current_account", &"")
	account_clearance = int(d.get("account_clearance", 0))
	login_day = int(d.get("login_day", 0))
	personnel_log = d.get("personnel_log", [])
	answered_emails = d.get("answered_emails", [])
	day = int(d.get("day", 0))
	called = d.get("called", [])
	caller_numbers = d.get("caller_numbers", {})
	account_passwords = d.get("account_passwords", {})
	SignalBus.scores_changed.emit(scores.duplicate())
