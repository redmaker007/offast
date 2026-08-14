extends Button




func _on_pressed() -> void:
	SignalBus.close_current_window_request.emit()
