extends popup_window

## 笔记本窗口：整个游戏画面里唯一的弹窗外壳。
##
## 开关只有两个入口，都在这一层收口：
##   开——点击桌面上的 laptop（clickable_item 发 open_laptop_request）
##   关——按红叉（cancel_button 直接调 WindowManager.close_current(owner)）
##
## 翻页完全由玩家驱动：每次打开都回到选择页，再由选择页上的按钮切去邮件 / 答题页。
## 回合状态不再参与翻页——后台状态怎么推进，笔记本里显示什么都不受影响。


## 笔记本里所有的内容页，翻页时只留目标页可见。
var _pages: Array[Control] = []


func _ready() -> void:
	super()
	_pages = [%laptop_select_page, %email_read_page, %instruction_execute_page]
	SignalBus.open_laptop_request.connect(_on_open_request)
	SignalBus.open_email_page_request.connect(_show_page.bind(%email_read_page))
	SignalBus.open_instruction_page_request.connect(_show_page.bind(%instruction_execute_page))
	_show_page(%laptop_select_page)


func _on_open_request() -> void:
	# 每次打开都从选择页起手，不管上次关窗时停在哪一页。
	_show_page(%laptop_select_page)
	WindowManager.open_window(self)


## 只切内容，不碰 open()/close()。
func _show_page(page: Control) -> void:
	for p in _pages:
		p.visible = (p == page)
