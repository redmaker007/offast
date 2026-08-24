extends Node

## 临时的截图工具：把几个覆盖层和笔记本各页摆出来各拍一张，存到 user://shots/。
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

	# 进上班时间，第 1 天的剧情信和私信才会灌进来。
	SignalBus.story_finished.emit()
	await _wait(0.4)

	# 笔记本：先拍登录页，再故意打错一次拍错误态。
	SignalBus.open_laptop_request.emit()
	await _wait(0.6)
	await _snap("login_page")

	var login := scene.get_node("%laptop_login_page")
	login.get_node("%login_user").text = "hrtemp"
	login.get_node("%login_pass").text = "nope"
	login._on_sign_in_pressed()
	await _wait(0.3)
	await _snap("login_failed")

	login.get_node("%login_user").text = "hrtemp"
	# 密码每局随机，问 GameState 要这一局的那个。
	login.get_node("%login_pass").text = GameState.account_password(&"hrtemp")
	login._on_sign_in_pressed()
	await _wait(0.4)
	await _snap("laptop_select")

	# 邮件页停在 B 派那封可回复的信上。
	SignalBus.open_email_page_request.emit()
	scene.get_node("email_reader").read_next_email()
	await _wait(0.4)
	await _snap("email_reply")

	# 人事表：四个动作按钮的符号（P / $↑ / $↓ / ✕）要一眼分得开。
	SignalBus.open_instruction_page_request.emit()
	await _wait(0.4)
	await _snap("instruction_page")

	# 档案页：低权限的号只查得到一部分人。
	SignalBus.open_profile_page_request.emit()
	await _wait(0.4)
	await _snap("profile_page_clearance_1")

	# 换成高权限的号，名单会变长。
	var book := scene.get_node("story_book")
	GameState.login(book.account_by_name(&"r_okafor"), 1)
	SignalBus.open_profile_page_request.emit()
	await _wait(0.4)
	await _snap("profile_page_clearance_2")
	await WindowManager.close_current(scene)
	await _wait(0.5)

	# 桌上那本记事本（玩家自己写字的地方）。
	SignalBus.open_notes_request.emit()
	await _wait(0.5)
	await _snap("notes_page")
	scene.get_node("notes_page").close()
	await _wait(0.4)

	# 拨号盘（直接开，跳过「先接当天来电」那一步）。
	var phone := scene.get_node("caller_page")
	phone.get_node("%dial_input").text = "0000"
	phone.open()
	await _wait(0.6)
	phone._on_call_pressed()
	await _wait(0.3)
	await _snap("caller_page")
	await phone.close()
	await _wait(0.4)

	# 桌面桥段：接电话那一段。
	SignalBus.open_caller_request.emit()
	await _wait(2.2)
	await _snap("event_page")
	scene.get_node("event_page").visible = false

	# 结算层：错一个，HR 那句要露出来。
	SignalBus.day_result_ready.emit({
		"day": 3, "days_to_win": 5, "correct": 2, "total": 3, "wrong": 1, "lives": 2,
	})
	await _wait(0.4)
	await _snap("result_overlay")
	scene.get_node("result_overlay").visible = false

	# 人事调动日志（结局前那一屏）。塞几条假记录，光看排版。
	for day in range(1, 4):
		GameState.log_personnel(day, {
			"employee": "Mira", "issuer": &"A", "complied": true,
			"actual": {"Fire": true}, "blank": false,
		})
		GameState.log_personnel(day, {
			"employee": "Jack", "issuer": &"", "complied": false,
			"actual": {}, "blank": true,
		})
	SignalBus.log_review_requested.emit()
	await _wait(0.4)
	await _snap("log_overlay")
	scene.get_node("log_overlay").visible = false

	# 结局层。现在按 id 取文案，直接喂一个 id 进去。
	SignalBus.ending_ready.emit(&"ground")
	await _wait(0.4)
	await _snap("ending_overlay")
	scene.get_node("ending_overlay").visible = false

	# 游戏内设置面板。
	scene._on_settings_pressed()
	await _wait(0.8)
	await _snap("ingame_settings")
	await WindowManager.close_current(scene)
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
