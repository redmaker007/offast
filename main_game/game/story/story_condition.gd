extends RefCounted
class_name story_condition

## `.story` 里那些 `if=` 的求值器。
##
## 故意做得很小：只有几种原子 + `and` / `not`。剧本里的条件都是
## 「A 分够不够」「鲍勃几级了」「第三天有没有 fire 掉瑞克」这种，
## 用不着完整的表达式引擎；语法越小，写错时报得越准。
##
## 语法：
##     score.A>=2           结局分比较（A/B/C/D，比较符 >= <= > < == !=）
##     level.Bob>=3         某人当前权限（没档案的人是 -1）
##     day>=4               今天是第几天
##     flag:took_the_call   剧情开关
##     did(promote,Bob)     **今天**给鲍勃批过 promotion
##     did(promote,Bob,day1)  第 1 天给过
##     did(promote,Bob,ever)  任意一天给过
##     did(fire,*random)    今天所有随机员工都被 fire 了
##     did(fire,*any)       今天至少 fire 了一个人
##     called(Mira)         打通过米拉的电话
##     leading(A)           A 这条结局线现在领先
##     tied(A,B)            两条线打平
##     var.mails_read>=3    关卡背景设定里的自定义变量（计数器之类，A/B/C/D 也能这么写）
##     inbox_empty          收件箱清空了（点门时判「活干完没有」）
##     not <条件>           取反
##     <条件> and <条件>     都满足
##     <条件> or <条件>      满足一个就行（or 比 and 松）
##
## 导入时用 validate() 检查一遍（错了当场报行号），运行时才 eval()。

## 条件里写的动作 → 人事表里的字面量。promote / promotion 都收，
## 写剧本时不用记单复数。
const ACTIONS := {
	"fire": "Fire",
	"raise": "Raise",
	"promotion": "Promotion",
	"promote": "Promotion",
	"reduction": "Reduction",
	"reduce": "Reduction",
}
const OPS := [">=", "<=", "==", "!=", ">", "<"]
const SCORE_KEYS := ["A", "B", "C", "D"]

const INBOX_EMPTY := "inbox_empty"

## email_reader 进的组，inbox_empty 靠它找到收件箱。
const INBOX_GROUP := &"email_reader"


## GameState 是 autoload，**编辑器里不存在**——导入 .story 时会跑到这个脚本，
## 直接写 `GameState.xxx` 会让整条依赖链在导入期编译失败（day_plan、email_def
## 全跟着挂）。所以运行期现查，查不到就当条件不成立。
static func _state() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("GameState")
	return null


## 条件成立吗。空条件永远成立（没写 if= 就是无条件）。
static func eval(text: String) -> bool:
	if text.strip_edges().is_empty():
		return true
	# or 比 and 松：先按 or 拆，任一支成立就成立。
	for alternative in _split_by(text, " or "):
		var ok := true
		for part in _split_by(alternative, " and "):
			if not _eval_term(part):
				ok = false
				break
		if ok:
			return true
	return false


## 语法检查。返回空串表示没问题，否则是给作者看的错误说明。
static func validate(text: String) -> String:
	if text.strip_edges().is_empty():
		return ""
	for alternative in _split_by(text, " or "):
		for part in _split_by(alternative, " and "):
			var error := _validate_term(part)
			if not error.is_empty():
				return error
	return ""


static func _split_by(text: String, sep: String) -> Array:
	var out: Array = []
	for part in text.split(sep, false):
		var t := String(part).strip_edges()
		if not t.is_empty():
			out.append(t)
	return out


static func _eval_term(term: String) -> bool:
	var t := term.strip_edges()
	if t.to_lower().begins_with("not "):
		return not _eval_term(t.substr(4))

	var gs := _state()
	if gs == null:
		return false

	if t.begins_with("flag:"):
		return gs.has_flag(StringName(t.substr(5).strip_edges()))

	if t == INBOX_EMPTY:
		return _inbox_empty()

	if t.to_lower().begins_with("did(") and t.ends_with(")"):
		return _eval_did(_args(t))

	if t.to_lower().begins_with("called(") and t.ends_with(")"):
		var args := _args(t)
		return gs.has_called(StringName(args[0] if args.size() > 0 else ""))

	if t.to_lower().begins_with("leading(") and t.ends_with(")"):
		var args := _args(t)
		return args.size() > 0 and gs.leading() == StringName(String(args[0]).to_upper())

	if t.to_lower().begins_with("tied(") and t.ends_with(")"):
		var args := _args(t)
		if args.size() < 2:
			return false
		return gs.tied(StringName(String(args[0]).to_upper()), StringName(String(args[1]).to_upper()))

	var cmp := _split_compare(t)
	if cmp.is_empty():
		push_warning("读不懂的条件（当成不成立）：%s" % term)
		return false
	return _compare(_value_of(cmp["left"]), cmp["op"], cmp["right"])


static func _validate_term(term: String) -> String:
	var t := term.strip_edges()
	if t.to_lower().begins_with("not "):
		return _validate_term(t.substr(4))

	if t.begins_with("flag:"):
		if t.substr(5).strip_edges().is_empty():
			return "flag: 后面要写开关名"
		return ""

	if t == INBOX_EMPTY:
		return ""

	if t.to_lower().begins_with("did("):
		if not t.ends_with(")"):
			return "did(...) 少了右括号：%s" % term
		var args := _args(t)
		if args.size() < 2 or args.size() > 3:
			return "did 要写成 did(动作,谁) 或 did(动作,谁,day3)：%s" % term
		if not ACTIONS.has(String(args[0]).to_lower()):
			return "did 的动作只能是 fire/raise/promotion/reduction：%s" % args[0]
		if args.size() == 3:
			var scope := String(args[2]).to_lower()
			if scope != "ever" and not (scope.begins_with("day") and scope.substr(3).is_valid_int()):
				return "did 的第三个参数只能是 ever 或 dayN：%s" % args[2]
		return ""

	if t.to_lower().begins_with("called("):
		if not t.ends_with(")"):
			return "called(...) 少了右括号：%s" % term
		if _args(t).is_empty():
			return "called 要写成 called(米拉)"
		return ""

	if t.to_lower().begins_with("leading(") or t.to_lower().begins_with("tied("):
		if not t.ends_with(")"):
			return "少了右括号：%s" % term
		var args := _args(t)
		var need := 2 if t.to_lower().begins_with("tied(") else 1
		if args.size() != need:
			return "leading 要写成 leading(A)，tied 要写成 tied(A,B)：%s" % term
		for a in args:
			if not (String(a).to_upper() in SCORE_KEYS):
				return "结局线只有 A/B/C/D：%s" % a
		return ""

	var cmp := _split_compare(t)
	if cmp.is_empty():
		return "读不懂的条件：%s" % term
	if not String(cmp["right"]).is_valid_int():
		return "比较的右边要是整数：%s" % term
	var left: String = cmp["left"]
	if left == "day":
		return ""
	if left.begins_with("score."):
		var key := left.substr(6).to_upper()
		if not (key in SCORE_KEYS):
			return "结局分只有 A/B/C/D：%s" % left
		return ""
	if left.begins_with("level."):
		if left.substr(6).strip_edges().is_empty():
			return "level. 后面要写员工名"
		return ""
	if left.begins_with("var."):
		# 变量有没有定义只有关卡知道，那一步归 level_validator。
		if left.substr(4).strip_edges().is_empty():
			return "var. 后面要写变量名"
		return ""
	return "读不懂的条件：%s" % term


# ── 原子求值 ────────────────────────────────────────────

static func _eval_did(args: Array) -> bool:
	var gs := _state()
	if gs == null or args.size() < 2:
		return false
	var action := _action_name(String(args[0]))
	var who := String(args[1])
	var scope := String(args[2]).to_lower() if args.size() > 2 else ""

	# 默认只看今天：剧本里绝大多数判定问的是「你今天做了什么」。
	var day: int = gs.day
	if scope == "ever":
		day = 0          # 0 = 不限定
	elif scope.begins_with("day"):
		day = int(scope.substr(3))

	match who:
		"*any":
			return gs.did_any(action, day)
		"*random":
			return gs.did_all_random(action, day)
	return gs.did(action, StringName(who), day)


static func _value_of(left: String) -> int:
	var gs := _state()
	if gs == null:
		return 0
	if left == "day":
		return gs.day
	if left.begins_with("score."):
		return gs.score_of(StringName(left.substr(6).to_upper()))
	if left.begins_with("level."):
		return gs.level_of(StringName(left.substr(6).strip_edges()))
	if left.begins_with("var."):
		return gs.var_of(StringName(left.substr(4).strip_edges()))
	return 0


## 收件箱是场景里的节点（email_reader 自己进这个组），不在 GameState 里。
## 场景不在（导入期、纯数据测试）就当没清空。
static func _inbox_empty() -> bool:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return false
	var reader := (loop as SceneTree).get_first_node_in_group(INBOX_GROUP)
	return reader != null and reader.remaining() == 0


static func _compare(value: int, op: String, right: String) -> bool:
	var target := int(right)
	match op:
		">=":
			return value >= target
		"<=":
			return value <= target
		">":
			return value > target
		"<":
			return value < target
		"==":
			return value == target
		"!=":
			return value != target
	return false


# ── 小工具 ──────────────────────────────────────────────

## 取括号里的参数，按逗号切。
static func _args(text: String) -> Array:
	var open_at := text.find("(")
	if open_at < 0 or not text.ends_with(")"):
		return []
	var inner := text.substr(open_at + 1, text.length() - open_at - 2)
	var out: Array = []
	for part in inner.split(",", false):
		var t := String(part).strip_edges()
		if not t.is_empty():
			out.append(t)
	return out


## 拆成 {left, op, right}，不是比较式就返回空字典。
static func _split_compare(text: String) -> Dictionary:
	for op in OPS:
		var at := text.find(op)
		if at > 0:
			return {
				"left": text.substr(0, at).strip_edges(),
				"op": op,
				"right": text.substr(at + op.length()).strip_edges(),
			}
	return {}


## 条件里写的动作名 → 人事表里用的字面量（"promote" / "promotion" → "Promotion"）。
static func _action_name(value: String) -> String:
	return str(ACTIONS.get(value.strip_edges().to_lower(), ""))
