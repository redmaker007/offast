extends Node

## 启动场景，只负责把控制权交给 SceneTransition。
##
## 场景实例从头到尾由路由器持有，这样它不会和 get_tree().current_scene 的
## 所有权打架——菜单和游戏都是路由器 add_child 出来的，不是 change_scene 换的。

const MENU_SCENE := "res://main_game/menu/menu_scene.tscn"


func _ready() -> void:
	SceneTransition.goto(MENU_SCENE, SceneTransition.Slide.NONE)
