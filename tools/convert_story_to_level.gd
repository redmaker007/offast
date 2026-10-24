extends SceneTree

## 一次性工具：把 res://story/zh 现有的内容转成 res://levels/main.level.json。
##
##     godot --headless --path <项目> -s res://tools/convert_story_to_level.gd
##
## 转完会跑一遍校验器，有错就打印出来、退出码非 0，不写文件。

const OUT := "res://levels/main.level.json"


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	var doc := level_converter.from_story_dir()
	var errs := level_validator.validate(doc)
	if not errs.is_empty():
		for e in errs:
			printerr(e.describe())
		return 1
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var err := level_store.write(OUT, doc)
	if not err.is_empty():
		printerr(err)
		return 1
	print("写好了：%s（%d 个外层节点）" % [OUT, doc.graph.nodes.size()])
	return 0
