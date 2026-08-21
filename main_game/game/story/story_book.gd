extends Node
class_name story_book

## 内容总入口：全局设定（账户 + 档案）和每天的剧本都从这一个节点上取。
##
## 之前是 day_book + profile_book 两个节点，找东西要先想「这归谁管」；
## 合成一个之后，「内容从哪来」只有一个答案。
##
## world 和 days 里挂的都是 story/ 下 .story 文本导入出来的资源，
## 不是手写的 .tres——改剧情去改文本文件。

## 内容根目录。下面按 locale 分文件夹：story/zh/world.story、story/zh/days/day_1.story……
## **不在 Inspector 里一个个挂资源**——换语言就是换目录，挂死了就换不了。
@export_dir var story_dir: String = "res://story"

## 找不到当前语言的目录时退到这个。
@export var fallback_locale: String = "zh"

## 最多找到第几天（找不到文件就停）。
@export var max_days: int = 12

## 当前语言这一份全局设定。
var world: world_book

## **下标 0 是第 1 天**。
var days: Array[day_plan] = []

## 现在装的是哪个语言的内容。
var loaded_locale := ""


func _ready() -> void:
	SignalBus.locale_changed.connect(_on_locale_changed)
	reload()


## 玩家换了语言：整套内容重装一遍。
## 局内换语言只换文本，不动进度——剧情资源是纯数据，进度在 GameState 里。
func _on_locale_changed(_loc: String) -> void:
	reload()


## 按当前语言重新装一遍内容。切语言时调。
func reload() -> void:
	var loc := _pick_locale()
	loaded_locale = loc
	world = _load_or_null("%s/%s/world.story" % [story_dir, loc]) as world_book
	days = []
	for i in range(1, max_days + 1):
		var plan := _load_or_null("%s/%s/days/day_%d.story" % [story_dir, loc, i]) as day_plan
		if plan == null:
			break
		days.append(plan)
	SignalBus.story_content_reloaded.emit(loc)


## 当前语言有内容就用它，没有就退到 fallback。
## TranslationServer 的 locale 可能是 "zh_CN" 这种，先按整串找，再按语言码找。
func _pick_locale() -> String:
	var current := TranslationServer.get_locale()
	for candidate in [current, current.split("_")[0], fallback_locale]:
		# 看的是「有没有 world.story」而不是「有没有这个文件夹」——
		# 空文件夹（比如刚开的 story/en/）会让整局内容变成空的。
		if candidate.is_empty():
			continue
		if ResourceLoader.exists("%s/%s/world.story" % [story_dir, candidate]):
			return candidate
	return fallback_locale


func _load_or_null(path: String) -> Resource:
	return load(path) if ResourceLoader.exists(path) else null


## 第 day 天（从 1 开始）的剧本。没配就返回 null，
## 调用方一律要能接受 null——那表示这一天退回纯随机玩法。
func plan_for(day: int) -> day_plan:
	var i := day - 1
	if i < 0 or i >= days.size():
		return null
	return days[i]


## 第 day 天点某个桌面物件时播哪一段。没配就是 null（点了没反应）。
##
## 便签不在这里：桌上那本是玩家自己写字的记事本（notes_page），
## 密码之类要留住的东西记在那本上，所以不需要「粘着上一天」这种补丁。
func event_for(day: int, key: StringName) -> conversation:
	var plan := plan_for(day)
	return plan.event_for(key) if plan != null else null


## 按 id 找一封剧情信的定义。id 在整局里唯一，所以不用先知道是第几天——
## 读档回来时收件箱里的信只剩 id，这条查询要能凭空把定义找回来。
func mail_def(id: StringName) -> email_def:
	if String(id).is_empty():
		return null
	for plan in days:
		if plan == null:
			continue
		for m in plan.scripted_emails:
			if m != null and m.id == id:
				return m
	return null


## 按名字找联系人。
func contact_by_name(contact_name: StringName) -> contact:
	if world == null:
		return null
	for c in world.contacts:
		if c != null and c.contact_name == contact_name:
			return c
	return null


## 按玩家拨的号码找联系人，没这个号返回 null（忙音）。
## 号码是这一局随机分配的，所以要回头问 GameState。
func contact_by_number(number: String) -> contact:
	var dialed := number.strip_edges()
	if dialed.is_empty() or world == null:
		return null
	for c in world.contacts:
		if c != null and GameState.caller_number(c.contact_name) == dialed:
			return c
	return null


func profile(employee_name: StringName) -> employee_profile:
	if world == null:
		return null
	for p in world.profiles:
		if p != null and p.employee_name == employee_name:
			return p
	return null


## 当前权限查得到的所有档案。查不到的人**根本不出现**——
## 「这个号查不到这个人」本身就是信息，不该灰着摆在那勾玩家。
func profiles_for(clearance: int) -> Array[employee_profile]:
	var out: Array[employee_profile] = []
	if world == null:
		return out
	for p in world.profiles:
		if p != null and p.clearance <= clearance:
			out.append(p)
	return out


## 用户名 + 密码对得上的账户，对不上返回 null。
func account_for(user: String, secret: String) -> account:
	if world == null:
		return null
	for a in world.accounts:
		if a != null and a.matches(user, secret):
			return a
	return null


## 按用户名找账户（读档恢复登录状态用，不校验密码）。
func account_by_name(username: StringName) -> account:
	if world == null:
		return null
	for a in world.accounts:
		if a != null and a.username == username:
			return a
	return null
