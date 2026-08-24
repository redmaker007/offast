@tool
extends EditorImportPlugin

## `.story` → day_plan / world_book。
##
## 一个文件产哪种资源看里面写了什么：有 [account]/[profile] 就是全局设定，
## 有 [story]/[mail]/桥段就是某一天的剧本，两类混在一个文件里会报错。
##
## 语法和报错信息都在 story_parser 里，这里只做「读文件 → 存资源」。
## 解析失败时把每条错误 push_error 出来（带文件名和行号），
## 并让导入失败——宁可当场红一片，也别让一个静悄悄的空资源混进游戏里。


func _get_importer_name() -> String:
	return "offast.story"


func _get_visible_name() -> String:
	return "Story Script"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["story"])


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	return "Resource"


## 导入格式版本。**改了解析器产出的资源结构就要 +1**，
## 否则 Godot 认为 .story 没变、继续用旧的 .res，跑起来是一堆空内容。
func _get_format_version() -> int:
	return 3


func _get_priority() -> float:
	return 1.0


func _get_import_order() -> int:
	return 0


func _get_preset_count() -> int:
	return 1


func _get_preset_name(_preset_index: int) -> String:
	return "Default"


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return []


func _get_option_visibility(_path: String, _option_name: StringName, _options: Dictionary) -> bool:
	return true


func _import(source_file: String, save_path: String, _options: Dictionary,
		_platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var f := FileAccess.open(source_file, FileAccess.READ)
	if f == null:
		push_error("读不了剧本文件：%s" % source_file)
		return ERR_CANT_OPEN

	var result := story_parser.parse(f.get_as_text(), source_file.get_file())
	f.close()

	for message in result.errors:
		push_error(message)
	if not result.ok():
		return ERR_PARSE_ERROR

	var out: Resource = result.day if result.day != null else result.world
	return ResourceSaver.save(out, "%s.%s" % [save_path, _get_save_extension()])
