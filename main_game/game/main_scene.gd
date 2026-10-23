extends Control

## 游戏主场景。只负责开局 / 读档这一个岔路，之后的流程都归 round_manager。


func _ready() -> void:
	randomize()
	await get_tree().process_frame
	if SaveState.is_restoring:
		# 这个实例是为读档建的：灌数据、驱动一次 UI 重绘，不要开新局把它冲掉。
		SaveState.load_game()
		SignalBus.game_restored.emit()
		return
	%round_manager.start_game()


## SceneTransition 挂起这个场景时调用（回主菜单）。
func _scene_suspended() -> void:
	SignalBus.game_suspended.emit()


## 右上角的齿轮。和菜单里是同一个 settings_panel.tscn，
## 走 WindowManager 是为了和笔记本/日历排队——它们不能同时开着。
func _on_settings_pressed() -> void:
	WindowManager.open_window(%settings_panel)
