extends popup_window

## 日历窗口：看今天是第几天、还剩几条命。
##
## 命数不写数字，直接放桌上那本日历的大图——图案本身就是隐喻。
## 图从桌面的 %calendar 那里取（四个槽位配在它身上），
## 这样弹窗和桌面永远显示同一张，不会出现两边对不上的情况。


func _ready() -> void:
	super()
	SignalBus.open_calendar_request.connect(_on_open_request)
	SignalBus.life_lost.connect(_on_life_lost)
	SignalBus.round_state_change.connect(_on_round_state_change)
	SignalBus.game_restored.connect(_refresh)


func _on_open_request() -> void:
	_refresh()
	WindowManager.open_window(self)


func _on_life_lost(_remaining: int) -> void:
	_refresh()


func _on_round_state_change(_rs) -> void:
	_refresh()


func _refresh() -> void:
	var rm = %round_manager
	%calendar_day.text = tr("UI_DAY_COUNT") % [rm.current_day, rm.days_to_win]
	%calendar_lives.texture = %calendar.current_face()
