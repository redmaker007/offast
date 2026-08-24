extends popup_window

## 笔记本窗口：整个游戏画面里唯一的弹窗外壳。
##
## 开关只有两个入口，都在这一层收口：
##   开——点击桌面上的 laptop（clickable_item 发 open_laptop_request）
##   关——按红叉（cancel_button 直接调 WindowManager.close_current(owner)）
##
## 翻页由玩家驱动，但**起点看有没有登录**：当天登过就落在选择页，没登过就落在
## 登录页，别的页一律进不去。电脑每天早上是锁的，所以每天上班第一件事是登录。
##
## 标题栏右上角那个按钮**一个键两用**：在选择页/登录页上是红叉（关笔记本），
## 翻进邮件/人事/档案页之后变成返回箭头（回选择页）。换的是图标和颜色，
## 位置不动——手不用挪，看一眼就知道现在按下去会发生什么。


## 标题栏那个按钮的两副面孔。红叉 = 关窗，箭头 = 回选择页。
@export var close_icon: Texture2D
@export var back_icon: Texture2D

## 关窗时那抹红，和返回时的米黄。
@export var close_tint: Color = Color(0.768, 0.478, 0.415)
@export var back_tint: Color = Color(0.909, 0.835, 0.690)

## 笔记本里所有的内容页，翻页时只留目标页可见。
var _pages: Array[Control] = []


func _ready() -> void:
	super()
	_pages = [%laptop_login_page, %laptop_select_page, %email_read_page,
		%instruction_execute_page, %profile_page]
	SignalBus.open_laptop_request.connect(_on_open_request)
	SignalBus.open_email_page_request.connect(_show_app.bind(%email_read_page))
	SignalBus.open_instruction_page_request.connect(_show_app.bind(%instruction_execute_page))
	SignalBus.open_profile_page_request.connect(_show_app.bind(%profile_page))
	# 邮件里点「查档案」：档案页自己会定位到那个人，这里只管翻页。
	SignalBus.profile_focus_requested.connect(_on_profile_focus_requested)
	SignalBus.login_succeeded.connect(_on_login_succeeded)
	SignalBus.logged_out.connect(_on_logged_out)
	_show_page(_home_page())


func _on_profile_focus_requested(_employee_name: StringName) -> void:
	_show_app(%profile_page)


func _on_login_succeeded(_signed_in) -> void:
	_show_page(%laptop_select_page)


func _on_logged_out() -> void:
	_show_page(%laptop_login_page)


## 标题栏那个按钮：在应用页上是返回，在选择页/登录页上是关窗。
func _on_cancel_pressed() -> void:
	if _can_go_back():
		_show_page(%laptop_select_page)
		return
	WindowManager.close_current(owner)


## 现在这一页有没有「上一页」可回。选择页和登录页没有。
func _can_go_back() -> bool:
	return not (%laptop_select_page.visible or %laptop_login_page.visible)


func _on_open_request() -> void:
	# 每次打开都从起手页开始，不管上次关窗时停在哪一页。
	_show_page(_home_page())
	WindowManager.open_window(self)


## 起手页：登录了是选择页，没登录是登录页。
func _home_page() -> Control:
	if GameState.is_logged_in():
		return %laptop_select_page
	return %laptop_login_page


## 翻到某个 app。没登录时一律弹回登录页——信号是全局的，
## 别的地方（比如邮件里的「查档案」）也能发，这里是唯一的关口。
func _show_app(page: Control) -> void:
	if not GameState.is_logged_in():
		_show_page(%laptop_login_page)
		return
	_show_page(page)


## 只切内容，不碰 open()/close()。
func _show_page(page: Control) -> void:
	for p in _pages:
		p.visible = (p == page)
	_refresh_corner_button()


## 换图标和颜色。**位置不变**——同一个位置、不同的样子，比多一个按钮省事，
## 也比「长得一样却干两件事」诚实。
func _refresh_corner_button() -> void:
	var going_back := _can_go_back()
	%cancel_button.icon = back_icon if going_back and back_icon != null else close_icon
	%cancel_button.modulate = back_tint if going_back else close_tint
