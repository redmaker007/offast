extends RefCounted
class_name level_content

## 节点里存的是文字（每种语言一份，沿用 .story 的写法），游戏要的是 conversation / email_def。
## 这里负责当场用 story_parser 解析，并按「节点 + 语言」缓存——中途换语言时再要一次就是另一种语言。
##
## 节点里的写法见 docs/level_engine.md 第 3 节：
##   剧情 bubble：props.script = {"zh": "them: …\nme: …", "en": …}，可以带 [dialogue x] 分支。
##   发信：props.mails = [{"id": "day3_rick", "script": {"zh": "[mail day3_rick from=…]\n…", …}}]，
##         外加 filler / filler_exclude / roster / conditional_roster 几个结构化字段。

var _cache := {}


## 剧情 bubble 的对话（当前语言）。没写或解析失败返回 null（播放器收到 null 会立刻结束，不卡玩家）。
func conversation_for(n: flow_node, locale := "") -> conversation:
	if n == null or not n.props.has("script"):
		return null
	var loc := _locale(locale)
	var key := "conv|%d|%s" % [n.get_instance_id(), loc]
	if _cache.has(key):
		return _cache[key]
	var text := level_doc.loc_text(n.props["script"], loc)
	var c: conversation = null
	if not text.strip_edges().is_empty():
		var r := story_parser.parse("[story]\n" + text, n.id)
		if r.ok() and r.day != null:
			c = r.day.story
		else:
			push_error("剧情 bubble %s 的 %s 文字解析失败：%s" % [n.id, loc, r.errors])
	_cache[key] = c
	return c


## 发信节点 → 一份 day_plan（只填发信用得到的格子），round_manager 照原来的规则发。
func plan_for_mail(n: flow_node, locale := "") -> day_plan:
	var loc := _locale(locale)
	var key := "mail|%d|%s" % [n.get_instance_id(), loc]
	if _cache.has(key):
		return _cache[key]
	var plan := day_plan.new()
	plan.filler_emails = int(n.props.get("filler", -1))
	for a in n.props.get("filler_exclude", []):
		plan.filler_exclude.append(StringName(str(a)))
	for who in n.props.get("roster", []):
		plan.story_roster.append(StringName(str(who)))
	for c in n.props.get("conditional_roster", []):
		if c is Dictionary:
			var rule := roster_rule.new()
			rule.employee_name = StringName(str(c.get("name", "")))
			rule.condition = str(c.get("if", ""))
			plan.conditional_roster.append(rule)
	for m in n.props.get("mails", []):
		var def := _parse_mail(m, loc, n.id)
		if def != null:
			plan.scripted_emails.append(def)
	_cache[key] = plan
	return plan


## 按 id 在整份关卡的发信节点里找一封剧情信（当前语言）。读档恢复收件箱、换语言重画邮件都靠它。
func mail_def(doc: level_doc, id: StringName, locale := "") -> email_def:
	if doc == null:
		return null
	var loc := _locale(locale)
	for outer_id in doc.graph.sorted_ids():
		var day: flow_node = doc.graph.node(outer_id)
		if day.body == null:
			continue
		for n in day.body.of_type("send_mail"):
			for def in plan_for_mail(n, loc).scripted_emails:
				if def.id == id:
					return def
	return null


## 换了天内图（测试换剧本）或者想强制重新解析时清缓存。
func clear() -> void:
	_cache.clear()


func _parse_mail(m: Variant, loc: String, node_id: String) -> email_def:
	if not m is Dictionary:
		return null
	var text := level_doc.loc_text(m.get("script", {}), loc)
	if text.strip_edges().is_empty():
		return null
	var r := story_parser.parse(text, "%s/%s" % [node_id, m.get("id", "")])
	if not r.ok() or r.day == null or r.day.scripted_emails.is_empty():
		push_error("发信节点 %s 里的邮件 %s（%s）解析失败：%s" % [node_id, m.get("id", ""), loc, r.errors])
		return null
	return r.day.scripted_emails[0]


static func _locale(locale: String) -> String:
	return locale if not locale.is_empty() else TranslationServer.get_locale().left(2)


## 校验用：这段剧情文字有没有语法错。返回空串表示没问题，否则是第一条错误。
static func check_dialogue(text: String) -> String:
	if text.strip_edges().is_empty():
		return ""
	var r := story_parser.parse("[story]\n" + text, "script")
	return "" if r.ok() else str(r.errors[0])


## 校验用：一封邮件的文字有没有语法错、是不是正好一封、id 和节点里登记的一样。
static func check_mail(text: String, id: String) -> String:
	if text.strip_edges().is_empty():
		return ""
	var r := story_parser.parse(text, id)
	if not r.ok():
		return str(r.errors[0])
	if r.day == null or r.day.scripted_emails.size() != 1:
		return "一封邮件的文字里要正好有一个 [mail] 块"
	if String(r.day.scripted_emails[0].id) != id:
		return "[mail] 块头的 id「%s」和登记的 id「%s」不一样" % [r.day.scripted_emails[0].id, id]
	return ""
