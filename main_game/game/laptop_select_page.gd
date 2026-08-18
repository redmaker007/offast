extends PanelContainer

## 笔记本首页：进笔记本先落在这一页，由玩家选择去邮件还是去答题。
##
## 这里只负责发信号，翻到哪一页由 laptop_page 决定。


func _on_email_button_pressed() -> void:
	SignalBus.open_email_page_request.emit()


func _on_instruction_button_pressed() -> void:
	SignalBus.open_instruction_page_request.emit()
