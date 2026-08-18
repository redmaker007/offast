extends PanelContainer

## 通用提示框：听 SignalBus.notice_requested，把话说出来，只有一个「OK」。
## 想弹提示的地方发信号就行，不用持有这个节点。
##
## 长相直接复用剧情那套对话气泡（bubble_view），所以配色、逐字机、打字音效
## 和剧情段是同一套，改一处两边都跟着变。气泡是「对方」side——提示是系统在跟
## 玩家说话，不是玩家自己的心声。没配头像，bubble_view 会把头像框收起来。
##
## 本体是铺满屏的遮罩（scrimPanel），所以提示是模态的——关掉之前点不了门、
## 点不了桌上的东西。弹出动画挂在里面的 %notice_card 上而不是遮罩上：
## 遮罩要是跟着一起缩放，屏幕四角会有一瞬间没盖住。
##
## 故意不走 WindowManager：那个管的是「同一时刻只开一个窗口」，
## 提示要能盖在笔记本上面，不该把玩家正在填的表顶掉。

## 每次提示都改这一条的 text 再重播，不用每次新建一个 Resource。
var _bubble := conversation_bubble.new()

## 提示还开着的时候又来一条：换文字重播一遍，但不重放弹出动画。
var _showing := false


func _ready() -> void:
	visible = false
	_bubble.side = conversation_bubble.Side.THEIRS
	%notice_bubble.advance_requested.connect(_on_ok_pressed)
	SignalBus.notice_requested.connect(_on_notice_requested)


func _on_notice_requested(text: String) -> void:
	_bubble.text = text
	%notice_bubble.show_bubble(_bubble)
	if _showing:
		return
	_showing = true
	visible = true
	%notice_card.open()


## 名字沿用「按了确认」的语义：接的是气泡的 advance_requested，
## 也就是玩家按下气泡上那个 OK。
func _on_ok_pressed() -> void:
	if not _showing:
		return
	_showing = false
	await %notice_card.close()
	visible = false
