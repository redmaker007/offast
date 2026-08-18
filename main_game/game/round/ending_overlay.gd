extends PanelContainer

## 结局层：被开除 / 通关。
##
## 到这一步这一局就结束了，回菜单时要把存档清掉，
## 否则菜单上的 Resume 会把一个已经结束的局读回来。

const MENU_SCENE := "res://main_game/menu/menu_scene.tscn"


func _ready() -> void:
	visible = false
	SignalBus.game_over.connect(_on_game_over)
	SignalBus.game_cleared.connect(_on_game_cleared)


func _on_game_over() -> void:
	_show("YOU'RE FIRED", "Three strikes. Security will walk you out.")


func _on_game_cleared() -> void:
	_show("YOU MADE IT", "Five days survived. See you Monday.")


func _show(title: String, body: String) -> void:
	%ending_title.text = title
	%ending_text.text = body
	visible = true


func _on_back_pressed() -> void:
	SaveState.clear()
	# 不挂起当前场景：这一局已经结束了，留着只会让 Resume 读回死局。
	SceneTransition.goto(MENU_SCENE, SceneTransition.Slide.FADE)
