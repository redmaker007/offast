extends Button

## 回主菜单：存盘 + 挂起当前这一局。
##
## 两套机制都走一遍——挂起负责这次会话里原样接着玩（UI 状态都在），
## 存盘负责关掉程序之后还能继续。

const MENU_SCENE := "res://main_game/menu/menu_scene.tscn"


func _on_pressed() -> void:
	SaveState.save_game()
	SceneTransition.goto(MENU_SCENE, SceneTransition.Slide.RIGHT, true)
