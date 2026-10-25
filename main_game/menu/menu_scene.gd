extends Control

## 主菜单。
##
## 「继续游戏」有两个来源，优先用前者：
##   1. 路由器里挂起的游戏实例——这次会话里回过菜单，那一局连 UI 状态都原样在
##   2. 磁盘存档——关过程序之后，新建实例再把数据灌进去

const GAME_SCENE := "res://main_game/game/main_scene.tscn"
const EDITOR_SCENE := "res://main_game/editor/level_editor.tscn"


func _ready() -> void:
	# 从游戏切回菜单时菜单是新实例化的（切走时没挂起菜单），所以 _ready 一定会跑。
	%continue_button.disabled = not (
		SceneTransition.has_retained(GAME_SCENE) or SaveState.has_save()
	)
	_add_editor_button()


## GM 模式开着才有「关卡编辑器」按钮，排在「退出」前面。
## 按钮在这里现做、不存进场景文件：以后要把入口藏起来，只改这一处。
func _add_editor_button() -> void:
	if not LocaleSettings.gm_mode:
		return
	var box: VBoxContainer = $background/VBoxContainer
	var b := Button.new()
	b.name = "editor_button"
	b.text = tr("UI_LEVEL_EDITOR")
	b.pressed.connect(_on_editor_pressed)
	var quit := box.get_node("quit_button")
	b.custom_minimum_size = quit.custom_minimum_size
	box.add_child(b)
	box.move_child(b, quit.get_index())


func _on_editor_pressed() -> void:
	SceneTransition.goto(EDITOR_SCENE, SceneTransition.Slide.LEFT)


func _on_new_game_pressed() -> void:
	SceneTransition.discard(GAME_SCENE)
	SaveState.clear()
	RoundState.current_round_state = RoundState.Round_State.STORY
	SceneTransition.goto(GAME_SCENE, SceneTransition.Slide.LEFT)


func _on_continue_pressed() -> void:
	if not SceneTransition.has_retained(GAME_SCENE):
		# 内存里没有挂起的实例，新建一个，并告诉它别自己开新局——
		# 它会在 _ready 里自己把存档读进来。
		#
		# 读档不能放在这里 await goto 之后做：菜单在转场途中就被销毁了，
		# await 醒过来时 self 已经是野指针。
		SaveState.begin_restore()
	SceneTransition.goto(GAME_SCENE, SceneTransition.Slide.LEFT)


func _on_settings_pressed() -> void:
	WindowManager.open_window(%settings_panel)


func _on_quit_pressed() -> void:
	get_tree().quit()
