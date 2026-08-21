extends PanelContainer

## 笔记本首页：登录之后落在这一页，由玩家选择去哪个 app。
##
## 这里只负责发信号，翻到哪一页由 laptop_page 决定。
## 多一个 Sign out：后面几天玩家会拿到别人的账号，换号就是从这里退出去重登。


func _ready() -> void:
	SignalBus.login_succeeded.connect(_on_login_succeeded)
	SignalBus.logged_out.connect(_on_logged_out)
	_refresh_account()


func _on_login_succeeded(_signed_in) -> void:
	_refresh_account()


func _on_logged_out() -> void:
	_refresh_account()


## 顶上那行「现在用谁的号登着」。换号玩法要靠它才看得出区别。
func _refresh_account() -> void:
	%signed_in_label.text = tr("UI_SIGNED_IN") % String(GameState.current_account)


func _on_email_button_pressed() -> void:
	SignalBus.open_email_page_request.emit()


func _on_instruction_button_pressed() -> void:
	SignalBus.open_instruction_page_request.emit()


func _on_profile_button_pressed() -> void:
	SignalBus.open_profile_page_request.emit()


func _on_sign_out_button_pressed() -> void:
	GameState.logout()
