extends PanelContainer

## 结局层：五种结局共用这一张卡（被开除 / 两个坏结局 / 底层 / 隐藏）。
##
## 放哪一个不由这里决定——ending_director 判完之后发 ending_ready 带 id 过来，
## 文案挂在它身上的 ending_def 里，改文案不用碰代码。
##
## 到这一步这一局就结束了，回菜单时要把存档清掉，
## 否则菜单上的 Resume 会把一个已经结束的局读回来。

const MENU_SCENE := "res://main_game/menu/menu_scene.tscn"


func _ready() -> void:
	visible = false
	SignalBus.ending_ready.connect(_on_ending_ready)


func _on_ending_ready(id: StringName) -> void:
	var d: ending_def = %ending_director.def_for(id)
	if d == null:
		push_warning("没有为结局 %s 配 ending_def" % id)
		%ending_title.text = tr("UI_THE_END")
		%ending_text.text = ""
	else:
		%ending_title.text = d.title
		%ending_text.text = d.body
	visible = true


func _on_back_pressed() -> void:
	SaveState.clear()
	# 不挂起当前场景：这一局已经结束了，留着只会让 Resume 读回死局。
	SceneTransition.goto(MENU_SCENE, SceneTransition.Slide.FADE)
