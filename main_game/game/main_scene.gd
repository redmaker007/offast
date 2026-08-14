extends Control




func _ready() -> void:
	randomize()
	# 关窗请求是全局的，接到 WindowManager 上，让窗口自己不用管别人。
	SignalBus.close_current_window_request.connect(WindowManager.close_current.bind(self))
	await get_tree().process_frame
	if SaveState.is_restoring:
		# 这个实例是为读档建的：灌数据、驱动一次 UI 重绘，不要开新局把它冲掉。
		SaveState.load_game()
		SignalBus.game_restored.emit()
		return
	%round_manager.start_new_round()
