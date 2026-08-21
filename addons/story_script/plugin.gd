@tool
extends EditorPlugin

## 把 .story 文本注册成可导入资源。真正的解析在 story_parser 里，
## 这一层只负责「编辑器保存文件之后自动跑一遍」。

const story_importer := preload("res://addons/story_script/story_importer.gd")

var _importer: EditorImportPlugin


func _enter_tree() -> void:
	_importer = story_importer.new()
	add_import_plugin(_importer)


func _exit_tree() -> void:
	remove_import_plugin(_importer)
	_importer = null
