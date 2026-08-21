extends PanelContainer

## 登录页：笔记本的第一页，没登录就卡在这。
##
## 密码是**剧情道具**——第 1 天写在桌上那张便签里，玩家自己敲进去。
## 所以这一页没有「已知账户」列表也没有自动填充：你记不住就回去翻便签
## （便签是粘的，见 story_book.event_for）。
##
## 每天早上电脑都是锁的（round_manager 开工时 logout），所以每天都要登一次；
## 后面几天拿到别人的号，就是在这一页换个用户名进去看更多档案。


func _ready() -> void:
	%login_error.text = ""
	%login_user.text_submitted.connect(_on_submitted)
	%login_pass.text_submitted.connect(_on_submitted)
	SignalBus.logged_out.connect(_clear)
	SignalBus.round_state_change.connect(_on_round_state_change)


func _on_round_state_change(_rs) -> void:
	# 新的一天电脑锁了，别把上一天敲的东西留在框里。
	_clear()


func _clear() -> void:
	%login_user.text = ""
	%login_pass.text = ""
	%login_error.text = ""


func _on_submitted(_text: String) -> void:
	_try_login()


func _on_sign_in_pressed() -> void:
	_try_login()


func _try_login() -> void:
	var signed_in: account = %story_book.account_for(%login_user.text, %login_pass.text)
	if signed_in == null:
		%login_error.text = tr("UI_LOGIN_FAILED")
		%login_pass.text = ""
		SignalBus.login_failed.emit()
		return
	%login_error.text = ""
	%login_pass.text = ""
	GameState.login(signed_in, %round_manager.current_day)
