extends RefCounted
class_name flow_graph

## 一张图：外层关卡图和每天的天内图都是它。只管存节点和互转字典，
## 合不合法归 level_validator。

## id -> flow_node。
var nodes: Dictionary = {}


func add(n: flow_node) -> flow_node:
	nodes[n.id] = n
	return n


## 按 id 取节点，没有就是 null。（不叫 get：会盖掉 Object.get。）
func node(id: String) -> flow_node:
	return nodes.get(id)


func has(id: String) -> bool:
	return nodes.has(id)


## 某种类型的全部节点，按 id 排好序——校验报错的顺序要稳定，测试和玩家看到的才一致。
func of_type(type: String) -> Array[flow_node]:
	var result: Array[flow_node] = []
	for id in sorted_ids():
		if nodes[id].type == type:
			result.append(nodes[id])
	return result


func sorted_ids() -> Array:
	var ids := nodes.keys()
	ids.sort()
	return ids


## 从 from_id 出发顺着所有出口能走到的节点 id（包括自己）。指向不存在节点的线跳过。
func reachable_from(from_id: String) -> Dictionary:
	var seen := {}
	if not nodes.has(from_id):
		return seen
	var stack: Array = [from_id]
	while not stack.is_empty():
		var id: String = stack.pop_back()
		if seen.has(id):
			continue
		seen[id] = true
		var n: flow_node = nodes[id]
		for port in n.outs:
			for t in n.targets(port):
				if nodes.has(t) and not seen.has(t):
					stack.append(t)
	return seen


## 能走到 goals 里任意一个节点的全部节点 id（反着走）。
func reaching(goals: Array) -> Dictionary:
	var incoming := {}
	for id in nodes:
		var n: flow_node = nodes[id]
		for port in n.outs:
			for t in n.targets(port):
				if not incoming.has(t):
					incoming[t] = []
				incoming[t].append(id)
	var seen := {}
	var stack: Array = goals.duplicate()
	while not stack.is_empty():
		var id: String = stack.pop_back()
		if seen.has(id) or not nodes.has(id):
			continue
		seen[id] = true
		for src in incoming.get(id, []):
			if not seen.has(src):
				stack.append(src)
	return seen


func to_dict() -> Dictionary:
	var d := {}
	for id in sorted_ids():
		d[id] = nodes[id].to_dict()
	return {"nodes": d}


static func from_dict(d: Dictionary) -> flow_graph:
	var g := flow_graph.new()
	var src: Dictionary = d.get("nodes", {})
	for id in src:
		if src[id] is Dictionary:
			g.add(flow_node.from_dict(str(id), src[id]))
	return g
