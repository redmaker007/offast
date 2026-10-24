extends RefCounted
class_name level_store

## 关卡文件的读写。
##
## res://levels/ 是原版（导出后只读），user://levels/ 里有同名文件就用它覆盖——
## 玩家在游戏里改过的关卡存在那儿，开发时改的也一样，最后再拷回 res://。
## 文件带版本号：比现在新的拒绝读（这一版的代码看不懂），比现在旧的以后在这里迁移。

const RES_DIR := "res://levels/"
const USER_DIR := "user://levels/"
const EXT := ".level.json"

## 一次读取的结果：doc 读成功才有，error 是给人看的原因（读成功时为空）。
class Result:
	extends RefCounted
	var doc: level_doc
	var path := ""
	var error := ""


## 按名字读关卡：先找 user://，没有再找 res://。
static func load_level(level_name: String) -> Result:
	var user_path := USER_DIR + level_name + EXT
	if FileAccess.file_exists(user_path):
		return read(user_path)
	return read(RES_DIR + level_name + EXT)


## 存到 user://（导出后唯一能写的地方）。返回空串表示成功，否则是原因。
static func save_level(level_name: String, doc: level_doc) -> String:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	return write(USER_DIR + level_name + EXT, doc)


static func read(path: String) -> Result:
	var r := Result.new()
	r.path = path
	if not FileAccess.file_exists(path):
		r.error = "找不到关卡文件：%s" % path
		return r
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		r.error = "%s 第 %d 行 JSON 格式错误：%s" % [path, json.get_error_line(), json.get_error_message()]
		return r
	if not json.data is Dictionary:
		r.error = "%s 不是一份关卡（最外层应该是一个对象）" % path
		return r
	var d: Dictionary = json.data
	if str(d.get("format", "")) != level_doc.FORMAT:
		r.error = "%s 不是关卡文件（format 应为 %s）" % [path, level_doc.FORMAT]
		return r
	var v := int(d.get("version", 0))
	if v > level_doc.VERSION:
		r.error = "%s 是第 %d 版格式，这个版本的游戏只认到第 %d 版" % [path, v, level_doc.VERSION]
		return r
	if v < 1:
		r.error = "%s 的 version 不对：%s" % [path, d.get("version")]
		return r
	d = _migrate(d, v)
	r.doc = level_doc.from_dict(d)
	return r


static func write(path: String, doc: level_doc) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "写不进 %s：%s" % [path, error_string(FileAccess.get_open_error())]
	doc.version = level_doc.VERSION
	f.store_string(JSON.stringify(doc.to_dict(), "\t"))
	f.close()
	return ""


## 旧版本格式升到现在的版本。现在只有第 1 版，什么都不用做。
static func _migrate(d: Dictionary, _from_version: int) -> Dictionary:
	return d
