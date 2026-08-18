extends Node

## 临时的截图工具：把几个覆盖层摆出来各拍一张，存到 user://shots/。
## 只为人眼看排版用，不是测试。跑法（要真渲染器，不能 --headless）：
##     <godot> --path . res://tests/screenshot_tool.tscn

const MAIN_SCENE := "res://main_game/game/main_scene.tscn"
const MENU_SCENE := "res://main_game/menu/menu_scene.tscn"
const OUT_DIR := "user://shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	await _shoot_game()
	await _shoot_menu()
	print("shots -> ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit()


func _shoot_game() -> void:
	var scene := (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(scene)
	await _wait(0.6)

	# 结算层：错一个，HR 那句要露出来。
	SignalBus.day_result_ready.emit({
		"day": 3, "days_to_win": 5, "correct": 2, "total": 3, "wrong": 1, "lives": 2,
	})
	await _wait(0.4)
	await _snap("result_overlay")
	scene.get_node("result_overlay").visible = false

	# 结局层。
	SignalBus.game_cleared.emit()
	await _wait(0.4)
	await _snap("ending_overlay")
	scene.get_node("ending_overlay").visible = false

	# 游戏内设置面板。
	scene._on_settings_pressed()
	await _wait(0.8)
	await _snap("ingame_settings")
	WindowManager.close_current(scene)
	await _wait(0.5)

	# 活没干完点门弹的提示。
	SignalBus.notice_requested.emit("Need to finish all the work first...")
	# 提示是逐字出的，等它打完再拍。
	await _wait(2.2)
	await _snap("notice_dialog")
	scene.get_node("notice_dialog")._on_ok_pressed()
	await _wait(0.5)

	remove_child(scene)
	scene.queue_free()
	await _wait(0.3)


func _shoot_menu() -> void:
	var menu := (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(menu)
	await _wait(0.5)
	menu._on_settings_pressed()
	await _wait(0.8)
	await _snap("menu_settings")
	remove_child(menu)
	menu.queue_free()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, name])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
