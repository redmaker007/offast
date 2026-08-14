@tool
extends EditorPlugin

## 名字 -> 脚本路径。插件启用时统一注册，禁用时统一注销。
const AUTOLOADS := {
	"SceneTransition": "res://addons/ui_polish/scene_transition.gd",
	"WindowManager": "res://addons/ui_polish/window_manager.gd",
}


func _enter_tree() -> void:
	for autoload_name in AUTOLOADS:
		add_autoload_singleton(autoload_name, AUTOLOADS[autoload_name])


func _exit_tree() -> void:
	for autoload_name in AUTOLOADS:
		remove_autoload_singleton(autoload_name)
