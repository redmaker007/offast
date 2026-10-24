extends RefCounted
class_name level_validator

## 关卡校验器：输入一份关卡，输出**全部**错误（不是碰到第一个就停）。
## 编辑器即时标红、游戏启动前拦截、无头测试共用这一份。
##
## 规则和错误代码见 docs/level_engine.md 第 8 节。报错顺序跟着节点 id 排序走，
## 同一份关卡每次报出来的顺序都一样。


static func validate(doc: level_doc) -> Array[level_error]:
	var errs: Array[level_error] = []
	_check_settings(doc, errs)
	_check_world(doc, errs)
	_check_outer(doc, errs)
	for n in doc.graph.of_type("day"):
		_check_body(doc, n, errs)
	_check_mail_ids(doc, errs)
	return errs


## 一份关卡能不能跑：没有任何错误。
static func is_valid(doc: level_doc) -> bool:
	return validate(doc).is_empty()


# ── 背景设定 / 世界表 ────────────────────────────────────

static func _check_settings(doc: level_doc, errs: Array[level_error]) -> void:
	var lives = doc.settings.get("lives", null)
	if not (lives is int or lives is float) or not int(lives) in level_doc.LIVES_OPTIONS:
		errs.append(level_error.new("LIVES_INVALID",
			{"value": lives, "options": ", ".join(level_doc.LIVES_OPTIONS.map(str))}))

	var seen := {}
	for id in doc.variable_ids():
		if seen.has(id):
			errs.append(level_error.new("DUP_VARIABLE", {"id": id}))
		seen[id] = true

	var fired := str(doc.settings.get("fired_ending", ""))
	if fired.is_empty():
		errs.append(level_error.new("FIRED_ENDING_MISSING"))
	else:
		var target := doc.graph.node(fired)
		if target == null or target.type != "day" or str(target.props.get("role", "")) != "ending":
			errs.append(level_error.new("FIRED_ENDING_NOT_ENDING", {"target": fired}))


static func _check_world(doc: level_doc, errs: Array[level_error]) -> void:
	for table in doc.world:
		if not doc.world[table] is Array:
			continue
		var seen := {}
		for row in doc.world[table]:
			if not row is Dictionary or not row.has("id"):
				continue
			var id := str(row["id"])
			if seen.has(id):
				errs.append(level_error.new("DUP_WORLD_ID", {"table": table, "id": id}))
			seen[id] = true


# ── 外层 ─────────────────────────────────────────────────

static func _check_outer(doc: level_doc, errs: Array[level_error]) -> void:
	var g := doc.graph
	var starts: Array = []
	var endings: Array = []

	for id in g.sorted_ids():
		var n: flow_node = g.node(id)
		if not node_types.is_known(node_types.OUTER, n.type):
			errs.append(level_error.new("UNKNOWN_TYPE", {"type": n.type}, "", id))
			continue
		match n.type:
			"day":
				var role := str(n.props.get("role", ""))
				if not role in node_types.ROLES:
					errs.append(level_error.new("BAD_ROLE", {"role": role}, "", id))
				elif role == "start":
					starts.append(id)
				elif role == "ending":
					endings.append(id)
					if _has_any_link(n):
						errs.append(level_error.new("ENDING_HAS_EXIT", {}, "", id))
			"brancher":
				var cases := node_types.branch_cases(n)
				_check_cases(n, doc.variable_ids(), "", errs)
			"jumper":
				var mode := str(n.props.get("mode", ""))
				if not mode in node_types.JUMP_MODES:
					errs.append(level_error.new("BAD_JUMP_MODE", {"mode": mode}, "", id))
		_check_ports(node_types.OUTER, g, n, "", errs)

	if starts.size() != 1:
		errs.append(level_error.new("START_COUNT", {"count": starts.size()}))
	if endings.is_empty():
		errs.append(level_error.new("NO_ENDING"))

	# 被开除随时可能发生，跳去的那个结局天也算一个入口，不能报成孤立。
	var extra := {}
	var fired := str(doc.settings.get("fired_ending", ""))
	if g.has(fired):
		extra = g.reachable_from(fired)
	_check_flow(g, starts, endings, "", extra, errs)


# ── 内层 ─────────────────────────────────────────────────

static func _check_body(doc: level_doc, day: flow_node, errs: Array[level_error]) -> void:
	if day.body == null:
		errs.append(level_error.new("DAY_BODY_MISSING", {}, "", day.id))
		return
	var g := day.body
	var d := day.id
	var objects := doc.object_ids()
	var variables := doc.variable_ids()
	var starts: Array = []
	var ends: Array = []
	var listened := {}

	for id in g.sorted_ids():
		var n: flow_node = g.node(id)
		if not node_types.is_known(node_types.INNER, n.type):
			errs.append(level_error.new("UNKNOWN_TYPE", {"type": n.type}, d, id))
			continue
		match n.type:
			"start":
				starts.append(id)
			"day_end":
				ends.append(id)
			"free_play":
				for t in n.targets("listen"):
					listened[t] = true
			"interactable":
				_check_object(n, objects, d, errs)
				_check_condition(str(n.props.get("unlock", "")), variables, d, id, errs)
			"window_bubble":
				_check_object(n, objects, d, errs)
			"story_bubble":
				var layer := str(n.props.get("layer", "event"))
				if not layer in node_types.STORY_LAYERS:
					errs.append(level_error.new("BAD_LAYER", {"layer": layer}, d, id))
				elif layer != "notice":
					_check_scripts(n.props.get("script", {}), "", d, id, errs)
			"send_mail":
				for m in n.props.get("mails", []):
					if m is Dictionary:
						_check_scripts(m.get("script", {}), str(m.get("id", "")), d, id, errs)
				for c in n.props.get("conditional_roster", []):
					if c is Dictionary:
						_check_condition(str(c.get("if", "")), variables, d, id, errs)
			"if":
				_check_cases(n, variables, d, errs)
			"effect":
				_check_condition(str(n.props.get("if", "")), variables, d, id, errs)
				var deltas = n.props.get("deltas", {})
				if deltas is Dictionary:
					for v in deltas:
						if not str(v) in variables:
							errs.append(level_error.new("UNKNOWN_VARIABLE", {"id": str(v)}, d, id))
		_check_ports(node_types.INNER, g, n, d, errs)

	if starts.size() != 1:
		errs.append(level_error.new("DAY_START_COUNT", {"count": starts.size()}, d))
	elif not _any_in(ends, g.reachable_from(starts[0])):
		errs.append(level_error.new("DAY_NO_END", {}, d))

	# 可互动物件只能从自由环节的 listen 进来：没人 listen 的报得更准，不当成普通孤立节点。
	var skip := {}
	for n in g.of_type("interactable"):
		if not listened.has(n.id):
			errs.append(level_error.new("NOT_LISTENED", {}, d, n.id))
			skip[n.id] = true

	for id in _chain_loops(g, d, errs):
		skip[id] = true

	_check_flow(g, starts, ends, d, skip, errs)


## 强制链绕成圈的节点（每个圈报一次）。返回圈里全部节点，后面就不再重复报「走不到结束」。
## 条件分支有多个出口，所以是在「强制链节点」组成的子图里找环（深搜，灰色节点再碰到就是环）。
static func _chain_loops(g: flow_graph, d: String, errs: Array[level_error]) -> Dictionary:
	var in_loop := {}
	var color := {}   # 没有 = 白，1 = 正在走（灰），2 = 走完（黑）
	for id in g.sorted_ids():
		if not color.has(id) and node_types.is_chain(g.node(id).type):
			_chain_dfs(g, id, [], color, in_loop, d, errs)
	return in_loop


static func _chain_dfs(g: flow_graph, id: String, stack: Array, color: Dictionary,
		in_loop: Dictionary, d: String, errs: Array[level_error]) -> void:
	color[id] = 1
	stack.append(id)
	var n: flow_node = g.node(id)
	for port in n.outs:
		for t in n.targets(port):
			if not g.has(t) or not node_types.is_chain(g.node(t).type):
				continue
			if color.get(t, 0) == 1:
				var loop := stack.slice(stack.find(t))
				var already := false
				for m in loop:
					if in_loop.has(m):
						already = true
					in_loop[m] = true
				if not already:
					loop.sort()
					errs.append(level_error.new("CHAIN_LOOP", {}, d, loop[0]))
			elif not color.has(t):
				_chain_dfs(g, t, stack, color, in_loop, d, errs)
	stack.pop_back()
	color[id] = 2


# ── 共用 ─────────────────────────────────────────────────

## 走不到（孤立）和走不出去（到不了终点）。只有一个入口时才查孤立，不然每个节点都会报。
static func _check_flow(g: flow_graph, starts: Array, goals: Array, d: String,
		skip: Dictionary, errs: Array[level_error]) -> void:
	var unreachable := {}
	if starts.size() == 1:
		var reach := g.reachable_from(starts[0])
		for id in g.sorted_ids():
			if not reach.has(id) and not skip.has(id):
				errs.append(level_error.new("UNREACHABLE", {}, d, id))
				unreachable[id] = true
	if goals.is_empty():
		return
	var ok := g.reaching(goals)
	for id in g.sorted_ids():
		if not ok.has(id) and not skip.has(id) and not unreachable.has(id):
			errs.append(level_error.new("NO_PATH_TO_END", {}, d, id))


## 出口一项项对照类型表：多接、少接、接错类型、接到不存在的节点。
static func _check_ports(kind: String, g: flow_graph, n: flow_node, d: String,
		errs: Array[level_error]) -> void:
	var specs := node_types.ports(kind, n)
	var names := {}
	for spec in specs:
		names[spec["name"]] = true

	for port in n.outs:
		if names.has(port) or n.targets(port).is_empty():
			continue
		# 结局天接了出口已经报过 ENDING_HAS_EXIT，不再报一遍「没有这个出口」。
		if kind == node_types.OUTER and n.type == "day" and str(n.props.get("role", "")) == "ending":
			continue
		errs.append(level_error.new("UNKNOWN_PORT", {"port": port}, d, n.id))

	for spec in specs:
		var port: String = spec["name"]
		var targets := n.targets(port)
		if targets.is_empty():
			if spec["required"]:
				errs.append(level_error.new("PORT_MISSING", {"port": port}, d, n.id))
			continue
		if targets.size() > 1 and not spec["multi"]:
			errs.append(level_error.new("TOO_MANY_TARGETS", {"port": port}, d, n.id))
		var allowed: Array = spec["targets"]
		for t in targets:
			if not g.has(t):
				errs.append(level_error.new("BAD_TARGET", {"port": port, "target": t}, d, n.id))
			elif not allowed.is_empty() and not g.node(t).type in allowed:
				errs.append(level_error.new("WRONG_TARGET_TYPE",
					{"port": port, "target": t, "target_type": g.node(t).type}, d, n.id))


## 剧情 / 邮件文字每种语言各解析一遍。mail_id 为空表示是剧情对话。
static func _check_scripts(script: Variant, mail_id: String, d: String, id: String,
		errs: Array[level_error]) -> void:
	if not script is Dictionary:
		return
	for loc in script:
		var text := str(script[loc])
		var detail := level_content.check_dialogue(text) if mail_id.is_empty() \
			else level_content.check_mail(text, mail_id)
		if not detail.is_empty():
			var params := {"locale": loc, "detail": detail}
			if not mail_id.is_empty():
				params["mail"] = mail_id
			errs.append(level_error.new("BAD_SCRIPT", params, d, id))


## 邮件 id 整份关卡里唯一：读档恢复收件箱、换语言重画都按 id 找。
static func _check_mail_ids(doc: level_doc, errs: Array[level_error]) -> void:
	var seen := {}
	for day in doc.graph.of_type("day"):
		if day.body == null:
			continue
		for n in day.body.of_type("send_mail"):
			for m in n.props.get("mails", []):
				if not m is Dictionary:
					continue
				var mid := str(m.get("id", ""))
				if seen.has(mid):
					errs.append(level_error.new("DUP_MAIL_ID", {"id": mid, "other": seen[mid]}, day.id, n.id))
				else:
					seen[mid] = "%s/%s" % [day.id, n.id]


## 分化器 / 条件分支的每一条条件。
static func _check_cases(n: flow_node, variables: Array[String], d: String, errs: Array[level_error]) -> void:
	for c in node_types.branch_cases(n):
		var cond := str(c.get("if", "")) if c is Dictionary else ""
		_check_condition(cond, variables, d, n.id, errs)


## 语法交给 story_condition；var.xxx 有没有定义只有关卡知道，在这里查。
static func _check_condition(cond: String, variables: Array[String], d: String, id: String,
		errs: Array[level_error]) -> void:
	var detail := story_condition.validate(cond)
	if not detail.is_empty():
		errs.append(level_error.new("BAD_CONDITION", {"detail": detail, "condition": cond}, d, id))
		return
	var re := RegEx.create_from_string("var[.]([A-Za-z0-9_]+)")
	for m in re.search_all(cond):
		if not m.get_string(1) in variables:
			errs.append(level_error.new("UNKNOWN_VARIABLE", {"id": m.get_string(1)}, d, id))


static func _check_object(n: flow_node, objects: Array[String], d: String, errs: Array[level_error]) -> void:
	var obj := str(n.props.get("object", ""))
	if not obj in objects:
		errs.append(level_error.new("UNKNOWN_OBJECT", {"object": obj}, d, n.id))


static func _has_any_link(n: flow_node) -> bool:
	for port in n.outs:
		if not n.targets(port).is_empty():
			return true
	return false


static func _any_in(ids: Array, pool: Dictionary) -> bool:
	for id in ids:
		if pool.has(id):
			return true
	return false
