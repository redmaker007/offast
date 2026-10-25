extends RefCounted
class_name level_doc

## 一份完整的关卡：背景设定 + 世界数据表 + 外层关卡图（天节点里装着天内图）。
## 只是数据，合不合法交给 level_validator，读写交给 level_store。
## 文件格式见 docs/level_engine.md 第 7 节。

const FORMAT := "offast-level"

## 现在的格式版本。改了格式就加一，并在 level_store 里写迁移。
const VERSION := 1

## 命数现在只开放这几个选项。
const LIVES_OPTIONS := [3]

var version: int = VERSION

## lives / fired_ending / variables，见 docs 第 4 节。
var settings: Dictionary = {}

## objects / accounts / profiles / contacts / names / endings，见 docs 第 5 节。
var world: Dictionary = {}

## 外层关卡图。
var graph: flow_graph = flow_graph.new()


## 一份空关卡，带默认设定（三条命、四条结局分线）。
static func create() -> level_doc:
	var doc := level_doc.new()
	doc.settings = {
		"lives": 3,
		"fired_ending": "",
		"variables": [
			{"id": "A", "kind": "score", "name": {"zh": "A", "en": "A"}},
			{"id": "B", "kind": "score", "name": {"zh": "B", "en": "B"}},
			{"id": "C", "kind": "score", "name": {"zh": "C", "en": "C"}},
			{"id": "D", "kind": "score", "name": {"zh": "D", "en": "D"}},
		],
	}
	doc.world = {"objects": []}
	return doc


## 变量 id 列表。
func variable_ids() -> Array[String]:
	var result: Array[String] = []
	for v in settings.get("variables", []):
		if v is Dictionary:
			result.append(str(v.get("id", "")))
	return result


## 按 id 找房间物件的记录，没有就是空字典。
func object(id: String) -> Dictionary:
	for o in world.get("objects", []):
		if o is Dictionary and str(o.get("id", "")) == id:
			return o
	return {}


## 房间物件 id 列表。
func object_ids() -> Array[String]:
	var result: Array[String] = []
	for o in world.get("objects", []):
		if o is Dictionary:
			result.append(str(o.get("id", "")))
	return result


func to_dict() -> Dictionary:
	return {
		"format": FORMAT,
		"version": version,
		"settings": settings.duplicate(true),
		"world": world.duplicate(true),
		"graph": graph.to_dict(),
	}


static func from_dict(d: Dictionary) -> level_doc:
	var doc := level_doc.new()
	doc.version = int(d.get("version", VERSION))
	doc.settings = flow_node.normalize_numbers((d.get("settings", {}) as Dictionary).duplicate(true))
	doc.world = flow_node.normalize_numbers((d.get("world", {}) as Dictionary).duplicate(true))
	doc.graph = flow_graph.from_dict(d.get("graph", {}))
	return doc


## 取多语言文字：{"zh": "…", "en": "…"} 里当前语言那份，没有就退回中文，再没有就随便一份。
static func loc_text(value: Variant, locale := "") -> String:
	if value is String:
		return value
	if not value is Dictionary or value.is_empty():
		return ""
	var loc := locale if not locale.is_empty() else TranslationServer.get_locale().left(2)
	if value.has(loc):
		return str(value[loc])
	if value.has("zh"):
		return str(value["zh"])
	return str(value.values()[0])
