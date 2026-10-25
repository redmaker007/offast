extends Control
class_name level_editor

## GM 关卡编辑器（第 4 阶段）。设计见 docs/level_engine.md 第 12 节。
##
## 界面全在代码里搭（场景文件只有一个根节点），用 Godot 默认的工具风格：
##   顶栏    关卡名 › 当前在哪一层，保存 / 重新读取 / 返回菜单
##   左边    元件栏：当前这一层能新建什么
##   中间    画布（GraphEdit）：拖节点、连线、删节点
##   右边    属性面板：选中节点的参数，条件边写边查语法
##   底部    错误列表：校验器的结果，点一条跳到出错的节点
##
## 4a 只有外层（天节点 / 分化器 / 天数跳转器）。天内画布是 4b。
## 改动只动内存里的 level_doc，点保存才写到 user://levels/（导出后也能存）。

const MENU_SCENE := "res://main_game/menu/menu_scene.tscn"

## 外层元件栏：类型 -> 按钮上的字。
const OUTER_PALETTE := {"day": "天节点", "brancher": "分化器", "jumper": "天数跳转器"}

const ROLE_LABELS := {"start": "初始天", "normal": "普通天", "ending": "结局天"}
const JUMP_LABELS := {"set": "设成第 N 天", "add": "加减 N 天"}

## 节点标题栏的颜色，按类型 / 天节点的 role。
const COLORS := {
	"start": Color(0.25, 0.55, 0.35),
	"normal": Color(0.3, 0.4, 0.6),
	"ending": Color(0.55, 0.3, 0.45),
	"brancher": Color(0.6, 0.45, 0.2),
	"jumper": Color(0.35, 0.5, 0.55),
}
const ERROR_TINT := Color(1.0, 0.65, 0.65)

## 读写哪一份关卡。
var level_name := "main"

var doc: level_doc
var errors: Array[level_error] = []

## 属性面板正在显示的节点 id。
var selected := ""

## 有没有没保存的改动。
var dirty := false

var _graph: GraphEdit
var _palette: VBoxContainer
var _inspector: VBoxContainer
var _error_list: ItemList
var _crumbs: Label
var _status: Label
var _leave_dialog: ConfirmationDialog


func _ready() -> void:
	_build_ui()
	reload()


# ── 读写 ───────────────────────────────────────────────

## 从磁盘读关卡（user:// 优先）。读不进来就开一份空关卡，并在状态栏说原因。
func reload() -> void:
	var r := level_store.load_level(level_name)
	if r.doc == null:
		load_doc(level_doc.create())
		_set_status("读不进关卡，开了一份空的：%s" % r.error)
		return
	load_doc(r.doc)
	_set_status("读取了 %s" % r.path)


## 直接编辑一份内存里的关卡（测试也用这个）。
func load_doc(d: level_doc) -> void:
	doc = d
	selected = ""
	dirty = false
	_refresh_all()


## 存到 user://levels/。返回空串表示成功。
func save() -> String:
	var err := level_store.save_level(level_name, doc)
	if err.is_empty():
		dirty = false
		_set_status("已保存到 %s%s%s" % [level_store.USER_DIR, level_name, level_store.EXT])
	else:
		_set_status("保存失败：" + err)
	return err


# ── 编辑操作（界面和测试都走这里） ─────────────────────────

func current_graph() -> flow_graph:
	return doc.graph


## 在画布上新建一个节点，返回它的 id。
func add_node(type: String, pos := Vector2.ZERO) -> String:
	var g := current_graph()
	var id := _unique_id(type)
	var n := g.add(flow_node.new(id, type))
	n.pos = pos
	match type:
		"day":
			n.props = {"role": "normal", "name": {"zh": id, "en": id}, "plan": 0}
			n.body = level_converter.work_day_body(0, {})
		"brancher":
			n.props = {"cases": []}
		"jumper":
			n.props = {"mode": "add", "value": 0}
	selected = id
	_changed()
	return id


## 删掉节点，连带拆掉所有指向它的线。
func delete_node(id: String) -> void:
	var g := current_graph()
	if not g.has(id):
		return
	g.nodes.erase(id)
	for other_id in g.nodes:
		var other: flow_node = g.nodes[other_id]
		for port in other.outs.keys():
			other.outs[port] = other.targets(port).filter(func(t): return t != id)
	if selected == id:
		selected = ""
	_changed()


## 从 from 的第 port_index 个出口连到 to。单出口会先拆掉原来的线。
func link(from: String, port_index: int, to: String) -> void:
	var n := current_graph().node(from)
	var specs := node_types.ports(node_types.OUTER, n) if n != null else []
	if port_index < 0 or port_index >= specs.size():
		return
	n.link(specs[port_index]["name"], to, not specs[port_index]["multi"])
	_changed()


func unlink(from: String, port_index: int, to: String) -> void:
	var n := current_graph().node(from)
	var specs := node_types.ports(node_types.OUTER, n) if n != null else []
	if port_index < 0 or port_index >= specs.size():
		return
	var port: String = specs[port_index]["name"]
	n.outs[port] = n.targets(port).filter(func(t): return t != to)
	_changed()


## 改一个节点的参数（属性面板用）。structural 为真时重画画布（出口数量可能变了）。
func set_prop(id: String, key: String, value: Variant, structural := false) -> void:
	var n := current_graph().node(id)
	if n == null:
		return
	n.props[key] = value
	_changed(structural)


## 分化器加一条条件（加在最后，else 前面）。
func add_case(id: String) -> void:
	var n := current_graph().node(id)
	var cases: Array = node_types.branch_cases(n).duplicate(true)
	cases.append({"if": ""})
	n.props["cases"] = cases
	_changed()


## 分化器删第 i 条条件：后面的条件和它们的出口线往前挪一格。
func remove_case(id: String, i: int) -> void:
	var n := current_graph().node(id)
	var cases: Array = node_types.branch_cases(n).duplicate(true)
	if i < 0 or i >= cases.size():
		return
	cases.remove_at(i)
	for k in range(i, cases.size()):
		n.outs[node_types.case_port(k)] = n.targets(node_types.case_port(k + 1))
	n.outs.erase(node_types.case_port(cases.size()))
	n.props["cases"] = cases
	_changed()


## 选中一个节点，属性面板换成它的。focus 为真时还在画布上选中它、把视野移过去（从错误列表跳过来时）。
func select(id: String, focus := false) -> void:
	selected = id
	var gn := _graph.get_node_or_null(NodePath(id)) as GraphNode
	if focus and gn != null:
		# set_selected 会再发一次 node_selected，回到这里时 focus 为假，不会绕圈。
		_graph.set_selected(gn)
		_graph.scroll_offset = gn.position_offset * _graph.zoom - _graph.size / 2.0 + gn.size / 2.0
	_rebuild_inspector()


## 一条错误对应画布上哪个节点：天内的错误先落在它所在的天节点上（天内画布是 4b）。
func error_target(e: level_error) -> String:
	return e.day if not e.day.is_empty() else e.node


func _changed(structural := true) -> void:
	dirty = true
	if structural:
		_rebuild_canvas()
	_revalidate()
	if structural:
		_rebuild_inspector()
	_set_status("有没保存的改动")


func _unique_id(type: String) -> String:
	var i := 1
	while current_graph().has("%s_%d" % [type, i]):
		i += 1
	return "%s_%d" % [type, i]


# ── 界面 ───────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	_crumbs = Label.new()
	top.add_child(_crumbs)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.7)
	top.add_child(_status)
	top.add_child(_button("重新读取", _on_reload_pressed))
	top.add_child(_button("保存", func(): save()))
	top.add_child(_button("返回菜单", _on_back_pressed))

	var middle := HSplitContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(middle)

	_palette = VBoxContainer.new()
	_palette.custom_minimum_size = Vector2(120, 0)
	middle.add_child(_palette)

	var right_split := HSplitContainer.new()
	middle.add_child(right_split)

	_graph = GraphEdit.new()
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph.right_disconnects = true
	_graph.connection_request.connect(_on_connection_request)
	_graph.disconnection_request.connect(_on_disconnection_request)
	_graph.delete_nodes_request.connect(_on_delete_nodes_request)
	_graph.node_selected.connect(func(gn: Node): select(String(gn.name)))
	_graph.end_node_move.connect(_on_end_node_move)
	right_split.add_child(_graph)

	var inspector_scroll := ScrollContainer.new()
	inspector_scroll.custom_minimum_size = Vector2(280, 0)
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_split.add_child(inspector_scroll)
	_inspector = VBoxContainer.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(_inspector)

	_error_list = ItemList.new()
	_error_list.custom_minimum_size = Vector2(0, 120)
	_error_list.item_selected.connect(_on_error_selected)
	root.add_child(_error_list)

	_leave_dialog = ConfirmationDialog.new()
	_leave_dialog.dialog_text = "有没保存的改动，确定离开？"
	_leave_dialog.confirmed.connect(_go_menu)
	add_child(_leave_dialog)


func _refresh_all() -> void:
	_crumbs.text = "%s  ›  关卡" % level_name
	_rebuild_palette()
	_rebuild_canvas()
	_revalidate()
	_rebuild_inspector()


func _rebuild_palette() -> void:
	_clear(_palette)
	var title := Label.new()
	title.text = "元件"
	_palette.add_child(title)
	for type in OUTER_PALETTE:
		var t: String = type
		_palette.add_child(_button(OUTER_PALETTE[t], func(): add_node(t, _view_center())))


func _view_center() -> Vector2:
	return ((_graph.scroll_offset + _graph.size / 2.0) / _graph.zoom).round()


func _rebuild_canvas() -> void:
	_graph.clear_connections()
	for c in _graph.get_children():
		if c is GraphNode:
			_graph.remove_child(c)
			c.queue_free()
	var g := current_graph()
	for id in g.sorted_ids():
		_graph.add_child(_make_graph_node(g.node(id)))
	for id in g.sorted_ids():
		var n: flow_node = g.node(id)
		var specs := node_types.ports(node_types.OUTER, n)
		for i in specs.size():
			for t in n.targets(specs[i]["name"]):
				if g.has(t):
					_graph.connect_node(id, i, t, 0)
	_tint_errors()


func _make_graph_node(n: flow_node) -> GraphNode:
	var gn := GraphNode.new()
	gn.name = n.id
	gn.title = _title_of(n)
	gn.position_offset = n.pos
	var color: Color = COLORS.get(str(n.props.get("role", "")) if n.type == "day" else n.type, Color.GRAY)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(4)
	gn.add_theme_stylebox_override("titlebar", sb)

	var specs := node_types.ports(node_types.OUTER, n)
	var rows := maxi(1, specs.size())
	for i in rows:
		var row := Label.new()
		if i < specs.size():
			row.text = _port_label(n, i, specs[i]["name"])
			row.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		else:
			row.text = _summary_of(n)
		row.custom_minimum_size = Vector2(150, 0)
		gn.add_child(row)
		gn.set_slot(i, i == 0, 0, Color.WHITE, i < specs.size(), 0, Color.WHITE)
	return gn


func _title_of(n: flow_node) -> String:
	match n.type:
		"day":
			return "%s · %s" % [ROLE_LABELS.get(str(n.props.get("role", "")), "天"),
				level_doc.loc_text(n.props.get("name", n.id), "zh")]
		"brancher":
			return "分化器 · %s" % n.id
		"jumper":
			return "跳转器 · %s" % n.id
	return "%s · %s" % [n.type, n.id]


func _port_label(n: flow_node, i: int, port: String) -> String:
	if n.type == "brancher" and port.begins_with("case_"):
		var cases := node_types.branch_cases(n)
		var cond := str(cases[i].get("if", "")) if i < cases.size() and cases[i] is Dictionary else ""
		return cond if not cond.is_empty() else "（空条件）"
	if n.type == "jumper":
		return "%s %d →" % ["设成" if str(n.props.get("mode", "")) == "set" else "加减", int(n.props.get("value", 0))]
	return port


func _summary_of(n: flow_node) -> String:
	if n.type == "day" and str(n.props.get("role", "")) == "ending":
		return "结局 %s" % n.props.get("ending", "?")
	return ""


func _revalidate() -> void:
	errors = level_validator.validate(doc)
	_error_list.clear()
	if errors.is_empty():
		_error_list.add_item("没有错误，可以跑")
		_error_list.set_item_selectable(0, false)
	for e in errors:
		var idx := _error_list.add_item(e.describe())
		_error_list.set_item_metadata(idx, e)
	_tint_errors()


func _tint_errors() -> void:
	var bad := {}
	for e in errors:
		bad[error_target(e)] = true
	for c in _graph.get_children():
		if c is GraphNode:
			c.self_modulate = ERROR_TINT if bad.has(String(c.name)) else Color.WHITE


func _rebuild_inspector() -> void:
	_clear(_inspector)
	var n := current_graph().node(selected) if not selected.is_empty() else null
	if n == null:
		_inspector.add_child(_label("点一个节点看它的属性。"))
		return
	_inspector.add_child(_label("%s（%s）" % [_title_of(n), n.id]))
	match n.type:
		"day":
			_inspect_day(n)
		"brancher":
			_inspect_brancher(n)
		"jumper":
			_inspect_jumper(n)
	_inspector.add_child(HSeparator.new())
	_inspector.add_child(_button("删除这个节点", func(): delete_node(n.id)))


func _inspect_day(n: flow_node) -> void:
	var names: Dictionary = n.props.get("name", {}) if n.props.get("name") is Dictionary else {}
	for loc in ["zh", "en"]:
		var l: String = loc
		_inspector.add_child(_label("名字（%s）" % l))
		var edit := LineEdit.new()
		edit.text = str(names.get(l, ""))
		edit.text_changed.connect(func(t: String):
			var d: Dictionary = n.props.get("name", {}) if n.props.get("name") is Dictionary else {}
			d[l] = t
			n.props["name"] = d
			_refresh_title(n)
			_changed(false))
		_inspector.add_child(edit)

	_inspector.add_child(_label("类型"))
	var role := _options(ROLE_LABELS, str(n.props.get("role", "normal")))
	role.item_selected.connect(func(i: int):
		var r: String = ROLE_LABELS.keys()[i]
		if r == "ending":
			n.outs.clear()
		set_prop(n.id, "role", r, true))
	_inspector.add_child(role)

	if str(n.props.get("role", "")) == "ending":
		_inspector.add_child(_label("结局 id（A / B / C / D / E）"))
		var ending := LineEdit.new()
		ending.text = str(n.props.get("ending", ""))
		ending.text_changed.connect(func(t: String): set_prop(n.id, "ending", t.strip_edges().to_upper()))
		_inspector.add_child(ending)
	else:
		_inspector.add_child(_label("用第几天的剧本（0 = 跟着天数）"))
		var plan := SpinBox.new()
		plan.max_value = 99
		plan.value = int(n.props.get("plan", 0))
		plan.value_changed.connect(func(v: float): set_prop(n.id, "plan", int(v)))
		_inspector.add_child(plan)

	var enter := _button("进入天内图（4b 做）", func(): pass)
	enter.disabled = true
	_inspector.add_child(enter)


func _inspect_brancher(n: flow_node) -> void:
	_inspector.add_child(_label("条件按顺序判，第一个成立的走；都不成立走 else。"))
	var cases := node_types.branch_cases(n)
	for i in cases.size():
		var idx := i
		_inspector.add_child(_label("条件 %d" % (i + 1)))
		var row := HBoxContainer.new()
		var edit := LineEdit.new()
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text = str(cases[i].get("if", "")) if cases[i] is Dictionary else ""
		row.add_child(edit)
		row.add_child(_button("删", func(): remove_case(n.id, idx)))
		_inspector.add_child(row)
		var check := _label("")
		_show_condition_check(check, edit.text)
		_inspector.add_child(check)
		edit.text_changed.connect(func(t: String):
			var cs: Array = node_types.branch_cases(n).duplicate(true)
			cs[idx] = {"if": t}
			n.props["cases"] = cs
			_show_condition_check(check, t)
			_refresh_ports_text(n)
			_changed(false))
	_inspector.add_child(_button("加一条条件", func(): add_case(n.id)))


func _inspect_jumper(n: flow_node) -> void:
	_inspector.add_child(_label("方式"))
	var mode := _options(JUMP_LABELS, str(n.props.get("mode", "add")))
	mode.item_selected.connect(func(i: int): set_prop(n.id, "mode", JUMP_LABELS.keys()[i], true))
	_inspector.add_child(mode)
	_inspector.add_child(_label("N"))
	var value := SpinBox.new()
	value.min_value = -99
	value.max_value = 99
	value.value = int(n.props.get("value", 0))
	value.value_changed.connect(func(v: float):
		n.props["value"] = int(v)
		_refresh_ports_text(n)
		_changed(false))
	_inspector.add_child(value)


func _show_condition_check(label: Label, cond: String) -> void:
	var detail := story_condition.validate(cond)
	if cond.strip_edges().is_empty():
		label.text = "（空条件 = 一定成立）"
		label.modulate = Color(1, 1, 1, 0.6)
	elif detail.is_empty():
		label.text = "✓ 语法正确"
		label.modulate = Color(0.6, 1.0, 0.6)
	else:
		label.text = "✗ " + detail
		label.modulate = Color(1.0, 0.6, 0.6)


## 只改节点标题 / 出口文字，不重画整个画布（打字时属性面板的输入框不会丢焦点）。
func _refresh_title(n: flow_node) -> void:
	var gn := _graph.get_node_or_null(NodePath(n.id)) as GraphNode
	if gn != null:
		gn.title = _title_of(n)


func _refresh_ports_text(n: flow_node) -> void:
	var gn := _graph.get_node_or_null(NodePath(n.id)) as GraphNode
	if gn == null:
		return
	var specs := node_types.ports(node_types.OUTER, n)
	for i in mini(specs.size(), gn.get_child_count()):
		(gn.get_child(i) as Label).text = _port_label(n, i, specs[i]["name"])


# ── 画布事件 ────────────────────────────────────────────

func _on_connection_request(from: StringName, from_port: int, to: StringName, _to_port: int) -> void:
	link(String(from), from_port, String(to))


func _on_disconnection_request(from: StringName, from_port: int, to: StringName, _to_port: int) -> void:
	unlink(String(from), from_port, String(to))


func _on_delete_nodes_request(names: Array) -> void:
	for nm in names:
		delete_node(String(nm))


func _on_end_node_move() -> void:
	for c in _graph.get_children():
		if c is GraphNode:
			var n := current_graph().node(String(c.name))
			if n != null:
				n.pos = c.position_offset
	dirty = true
	_set_status("有没保存的改动")


func _on_error_selected(index: int) -> void:
	var e = _error_list.get_item_metadata(index)
	if e is level_error:
		var target := error_target(e)
		if current_graph().has(target):
			select(target, true)


func _on_reload_pressed() -> void:
	reload()


func _on_back_pressed() -> void:
	if dirty:
		_leave_dialog.popup_centered()
		return
	_go_menu()


func _go_menu() -> void:
	SceneTransition.goto(MENU_SCENE, SceneTransition.Slide.RIGHT)


# ── 小工具 ──────────────────────────────────────────────

func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _options(labels: Dictionary, current: String) -> OptionButton:
	var o := OptionButton.new()
	var keys := labels.keys()
	for i in keys.size():
		o.add_item(labels[keys[i]], i)
	o.select(maxi(0, keys.find(current)))
	return o


static func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
