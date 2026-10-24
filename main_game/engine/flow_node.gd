extends RefCounted
class_name flow_node

## 图里的一个节点。外层（天节点 / 分化器 / 天数跳转器）和内层（天内图的各个元件）
## 共用这一个结构，区别只在 type 和 props——编辑器画布、校验器、存盘都只认这一套。
##
## 设计见 docs/level_engine.md。

## 稳定的字串 id，同一张图里不重复。存档、条件、连线都靠它，别用下标。
var id: String = ""

## 节点类型，见 node_types。
var type: String = ""

## 在画布上的位置。
var pos: Vector2 = Vector2.ZERO

## 这种类型自己的参数（role、条件、引用的物件……），原样存进 JSON。
var props: Dictionary = {}

## 出口名 -> 目标节点 id 的数组。单出口的数组最多一个元素。
var outs: Dictionary = {}

## 只有天节点有：里面那张天内图。
var body: flow_graph = null


func _init(p_id := "", p_type := "") -> void:
	id = p_id
	type = p_type


## 这个出口接到了哪些节点。
func targets(port: String) -> Array[String]:
	var result: Array[String] = []
	for t in outs.get(port, []):
		result.append(str(t))
	return result


## 第一个目标，没接就是空串。单出口用这个。
func target(port: String) -> String:
	var t := targets(port)
	return t[0] if not t.is_empty() else ""


## 接一条线。single 为真时先把这个出口原来的线拆掉。
func link(port: String, to_id: String, single := true) -> void:
	if single or not outs.has(port):
		outs[port] = []
	if not to_id in outs[port]:
		outs[port].append(to_id)


func unlink(port: String) -> void:
	outs.erase(port)


func to_dict() -> Dictionary:
	var d := {
		"type": type,
		"pos": [pos.x, pos.y],
		"props": props.duplicate(true),
		"outs": outs.duplicate(true),
	}
	if body != null:
		d["body"] = body.to_dict()
	return d


static func from_dict(p_id: String, d: Dictionary) -> flow_node:
	var n := flow_node.new(p_id, str(d.get("type", "")))
	var p: Array = d.get("pos", [0, 0])
	if p.size() >= 2:
		n.pos = Vector2(float(p[0]), float(p[1]))
	n.props = normalize_numbers((d.get("props", {}) as Dictionary).duplicate(true))
	# JSON 读回来的出口值可能是单个字串（手写的文件），统一成数组。
	for port in (d.get("outs", {}) as Dictionary):
		var v = d["outs"][port]
		var list: Array = []
		if v is Array:
			for t in v:
				list.append(str(t))
		elif v != null and str(v) != "":
			list.append(str(v))
		n.outs[str(port)] = list
	if d.has("body") and d["body"] is Dictionary:
		n.body = flow_graph.from_dict(d["body"])
	return n


## JSON 里的数字一律读成 float，3 会变成 3.0——比较、显示、再存回去都会走样。
## 递归把「其实是整数」的 float 转回 int。数据里没有需要保留 3.0 这种写法的字段。
static func normalize_numbers(v: Variant) -> Variant:
	if v is float and v == floorf(v) and absf(v) < 9.0e15:
		return int(v)
	if v is Array:
		for i in v.size():
			v[i] = normalize_numbers(v[i])
	elif v is Dictionary:
		for k in v:
			v[k] = normalize_numbers(v[k])
	return v
