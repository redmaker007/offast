extends Node

## 基于组的存档管理器（autoload SaveState）。
##
## 想被存的节点做三件事，管理器对存的内容一无所知，所以换个项目照样能用：
##   1. _ready 里 add_to_group(SaveState.GROUP)
##   2. 有一个全局唯一的 save_id 属性（用显式 id 而不是 NodePath，
##      以后改场景结构不会把旧存档作废）
##   3. 实现 save_data() -> Dictionary 和 load_data(d: Dictionary) -> void
##
## 存档用 var_to_str() 写文本，不用 JSON：JSON 会把 int 变成 float
## （存 3 读出来是 3.0，拼进字符串就成了 "Level:3.0"），var_to_str 精确保留
## int / Array / Dictionary 类型，而且开发期可以直接打开文件核对。
##
## save_data() 里的自定义对象（纯数据 RefCounted）交给 object_packer 自动处理，
## 数据类本身不用写任何存档代码。

const GROUP := "persist"
const SAVE_DIR := "user://saves"

signal saved(slot: String)
signal loaded(slot: String)

## 读档流程正在进行中：场景已经在建了，但数据还没灌进去。
## 场景可以在 _ready 里查这个标志，决定要不要自动开新局——不然会先跑一遍
## 开局逻辑（发邮件、播音效），紧接着又被存档覆盖掉。
var is_restoring := false


## 告诉管理器"接下来这个场景是为读档而建的"。在 goto 之前调用。
func begin_restore() -> void:
	is_restoring = true


func slot_path(slot: String) -> String:
	return "%s/%s.sav" % [SAVE_DIR, slot]


func has_save(slot := "default") -> bool:
	return FileAccess.file_exists(slot_path(slot))


## 收集 persist 组里所有节点的 save_data() 写入存档。
func save_game(slot := "default") -> bool:
	var payload := {}
	for node in get_tree().get_nodes_in_group(GROUP):
		var id := _id_of(node)
		if id.is_empty():
			push_error("persist 组里的节点没有 save_id：%s" % node.get_path())
			continue
		if not node.has_method("save_data"):
			push_error("persist 组里的节点没有实现 save_data()：%s" % node.get_path())
			continue
		if payload.has(id):
			push_error("save_id 重复，后一个被跳过：%s（%s）" % [id, node.get_path()])
			continue
		payload[id] = object_packer.pack(node.save_data())

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("存档写入失败（%s）：%s" % [slot_path(slot), FileAccess.get_open_error()])
		return false
	f.store_string(var_to_str(payload))
	f.close()

	saved.emit(slot)
	return true


## 把存档灌回 persist 组里对应 save_id 的节点。
## 注意这只恢复数据，UI 不会自己刷新——调用方负责在之后驱动一次重绘。
func load_game(slot := "default") -> bool:
	is_restoring = false

	if not has_save(slot):
		return false
	var f := FileAccess.open(slot_path(slot), FileAccess.READ)
	if f == null:
		push_error("存档读取失败（%s）：%s" % [slot_path(slot), FileAccess.get_open_error()])
		return false
	var text := f.get_as_text()
	f.close()

	var payload: Variant = str_to_var(text)
	if not (payload is Dictionary):
		push_error("存档内容不是字典，可能已损坏：%s" % slot_path(slot))
		return false

	for node in get_tree().get_nodes_in_group(GROUP):
		var id := _id_of(node)
		if id.is_empty() or not payload.has(id):
			continue
		if not node.has_method("load_data"):
			push_error("persist 组里的节点没有实现 load_data()：%s" % node.get_path())
			continue
		node.load_data(object_packer.unpack(payload[id]))

	loaded.emit(slot)
	return true


## 删掉存档。
func clear(slot := "default") -> void:
	is_restoring = false
	if not has_save(slot):
		return
	DirAccess.remove_absolute(slot_path(slot))


func _id_of(node: Node) -> String:
	var id: Variant = node.get("save_id")
	if id == null:
		return ""
	return str(id)
