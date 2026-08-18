@tool
extends Control
class_name bubble_view

## 传统 RPG 那个对话框：一次显示一条 conversation_bubble。
##
## 只管「怎么演一条」，不知道整段剧情长什么样——播到哪、下一条是谁，全归 story_page。
## 演完一条就发信号出去，等外面喂下一条。
##
## 两种模式靠 visible 切：
##   文字模式   —— next_button 显示，choice_list 隐藏
##   选择题模式 —— 反过来
##
## 逐字机跑的是 Label 的 visible_characters。打字途中按 next：
##   can_skip = true  —— 立刻把全文刷出来（再按一次才切下一条）
##   can_skip = false —— 按钮是灰的，按不动，重要剧情逼玩家看完
##
## 底板不是手绘图，是场景里 plate 上挂的 StyleBoxFlat（圆角矩形）。
## 想改配色、圆角、描边，直接在 Inspector 里点开那个 StyleBoxFlat 改，不用出图。


## 普通气泡：文字出完了，玩家按下 next。
signal advance_requested()

## 选择题：玩家选了第 index 个。
signal choice_picked(index: int, choice: conversation_choice)


@export_group("外观")

## 对方 / 我方各自的底板样式。**两个都留空就用场景里 plate 上那个**（默认的圆角米黄底板）。
## 想让两边长得不一样，就在这里各挂一个 StyleBoxFlat。
@export var plate_style_theirs: StyleBox
@export var plate_style_mine: StyleBox

## 气泡自己没配头像时用这张。**留空的话头像框整个收起来**，
## 不会剩一个空框——提示气泡（notice_dialog）就是这种没头像的用法。
@export var default_avatar: Texture2D

## 推进按钮上的字。一次性的提示气泡叫「OK」比「Next」自然。
@export var advance_text: String = "Next":
	set(value):
		advance_text = value
		if is_node_ready():
			%next_button.text = value


@export_group("编辑器预览")

## **只影响编辑器里的摆位**，方便对着调两侧的排版。
## 运行时哪边说话由气泡自己的 side 决定，跟这个没关系。
@export var preview_side := conversation_bubble.Side.THEIRS:
	set(value):
		preview_side = value
		if Engine.is_editor_hint() and is_node_ready():
			_layout_side(value == conversation_bubble.Side.MINE)


@export_group("逐字机")

## 每秒冒几个字。<= 0 就是不逐字，一次全出。
@export var chars_per_second: float = 30.0

## 打字音效。留空就不响。走 SFX 总线，音量归设置面板的 SFX 滑块管。
@export var type_sound: AudioStream

## 每冒几个字响一声。1 = 每个字都响；字太密就调大。<= 0 也是不响。
## 空格和换行不算数——停顿的地方响一声很怪。
@export var sound_every_chars: int = 2

@export_range(-60.0, 12.0, 0.1, "suffix:dB") var type_volume_db: float = 0.0

## 每声随机偏一点音高，免得听起来像机关枪。0 = 每声都一样。
@export_range(0.0, 0.5, 0.01) var type_pitch_jitter: float = 0.08


@export_group("选项按钮")

## 选项按钮是按 choices 动态生成的，这里配它们长什么样。
@export var choice_button_min_size: Vector2 = Vector2(320, 48)
@export var choice_button_variation: StringName = &"LongButton"


var _bubble: conversation_bubble = null
var _text_done := false

## 逐字机走的是 _process 而不是 tween：要在每冒一个字的那一刻响一声，
## tween 只能事后去查 visible_characters 变了没有，绕一道还不准。
var _typing := false
## 已经冒出来的字数，带小数——每帧按 chars_per_second * delta 累加。
var _revealed := 0.0
var _total := 0
## 距离上次响声又冒了几个（非空白）字。
var _since_sound := 0

var _audio: AudioStreamPlayer

## 场景里 plate 原本挂的样式。两个 @export 都留空时回退到它，
## 顺便保证「我方配了样式、对方没配」时不会把我方那张留在对方身上。
var _default_plate_style: StyleBox


func _ready() -> void:
	_default_plate_style = %plate.get_theme_stylebox("panel")
	%next_button.text = advance_text

	if Engine.is_editor_hint():
		# 编辑器里只摆一下左右，别去连信号、别去建 AudioStreamPlayer。
		set_process(false)
		_layout_side(preview_side == conversation_bubble.Side.MINE)
		return

	%next_button.pressed.connect(_on_next_pressed)
	_clear_choices()

	_audio = AudioStreamPlayer.new()
	# 挂 SFX 总线，音量就归设置面板的 SFX 滑块管。
	# 项目里没有这条总线就留在 Master，不影响出声。
	if AudioServer.get_bus_index("SFX") >= 0:
		_audio.bus = &"SFX"
	add_child(_audio)

	set_process(false)


## 演一条气泡。演完会发 advance_requested 或 choice_picked。
func show_bubble(b: conversation_bubble) -> void:
	_bubble = b
	if b == null:
		return

	_apply_plate(b)
	# 头像要先摆：有没有头像框会影响文字往哪边靠。
	_apply_avatar(b)
	_apply_side(b)
	_clear_choices()

	# 先一律进文字模式，文字出完了再决定要不要换成选择题。
	%choice_list.visible = false
	%next_button.visible = true
	%next_button.disabled = not b.can_skip

	_start_typing(b.text)


## 文字有没有出完。story_page 存档 / 跳过时会问。
func is_text_done() -> bool:
	return _text_done


## 立刻把全文刷出来，不管 can_skip。外部要强制跳过时用。
func finish_typing() -> void:
	_stop_typing()
	%text_box.visible_characters = -1
	_on_text_done()


# ── 逐字机 ──────────────────────────────────────────────

func _start_typing(text: String) -> void:
	_stop_typing()
	_text_done = false
	%text_box.text = text

	_total = text.length()
	if chars_per_second <= 0.0 or _total == 0:
		finish_typing()
		return

	%text_box.visible_characters = 0
	_revealed = 0.0
	_since_sound = 0
	_typing = true
	set_process(true)


func _process(delta: float) -> void:
	if not _typing:
		return
	var before := int(_revealed)
	_revealed = minf(_revealed + chars_per_second * delta, float(_total))
	var now := int(_revealed)
	if now != before:
		%text_box.visible_characters = now
		_on_chars_revealed(before, now)
	if now >= _total:
		finish_typing()


func _stop_typing() -> void:
	_typing = false
	set_process(false)


## 这一帧新冒出来的是 [from, to) 这几个字，看要不要响一声。
func _on_chars_revealed(from: int, to: int) -> void:
	if type_sound == null or sound_every_chars <= 0:
		return
	var text: String = %text_box.text
	for i in range(maxi(from, 0), mini(to, text.length())):
		# 空格和换行跳过：停顿的地方响一声很怪。
		if text[i].strip_edges().is_empty():
			continue
		_since_sound += 1
		if _since_sound >= sound_every_chars:
			_since_sound = 0
			_play_type_sound()


## 单个 player 就够：打字声很短，被下一声掐掉正是想要的效果。
func _play_type_sound() -> void:
	_audio.stream = type_sound
	_audio.volume_db = type_volume_db
	_audio.pitch_scale = 1.0 + randf_range(-type_pitch_jitter, type_pitch_jitter)
	_audio.play()


func _on_text_done() -> void:
	_text_done = true
	if _bubble == null:
		return
	if _bubble.is_choice():
		# 换成选择题模式：next 收起来，选项摆出来。
		%next_button.visible = false
		_build_choices(_bubble.choices)
		%choice_list.visible = true
	else:
		%next_button.disabled = false


# ── 输入 ────────────────────────────────────────────────

func _on_next_pressed() -> void:
	if not _text_done:
		# 打字途中按 next = 提前把全文刷出来。can_skip 为 false 时按钮本来就是灰的，
		# 走不到这儿；这里再挡一道，免得以后有人从代码里直接调。
		if _bubble != null and _bubble.can_skip:
			finish_typing()
		return
	advance_requested.emit()


func _on_choice_pressed(index: int) -> void:
	if _bubble == null or index < 0 or index >= _bubble.choices.size():
		return
	# 选完立刻锁住，免得连点两下发两次。
	_set_choices_disabled(true)
	choice_picked.emit(index, _bubble.choices[index])


# ── 选项按钮 ────────────────────────────────────────────

func _build_choices(choices: Array[conversation_choice]) -> void:
	_clear_choices()
	for i in range(choices.size()):
		var c: conversation_choice = choices[i]
		if c == null:
			continue
		var b := Button.new()
		b.text = c.text
		b.custom_minimum_size = choice_button_min_size
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if not String(choice_button_variation).is_empty():
			b.theme_type_variation = choice_button_variation
		b.pressed.connect(_on_choice_pressed.bind(i))
		%choice_list.add_child(b)


func _clear_choices() -> void:
	for c in %choice_list.get_children():
		%choice_list.remove_child(c)
		c.queue_free()


func _set_choices_disabled(on: bool) -> void:
	for c in %choice_list.get_children():
		if c is Button:
			c.disabled = on


# ── 素材 ────────────────────────────────────────────────

## 底板样式。两个 @export 都没配就用场景里那个，永远不会变成空白。
func _apply_plate(b: conversation_bubble) -> void:
	var sb: StyleBox = plate_style_mine if b.side == conversation_bubble.Side.MINE else plate_style_theirs
	if sb == null:
		sb = _default_plate_style
	if sb != null:
		%plate.add_theme_stylebox_override("panel", sb)


## 头像在哪边：我方在左、对方在右。头像框和文字一起靠那一侧，
## 另一侧留白——所以两边说话时气泡的重心是错开的，一眼能看出是谁在说。
func _apply_side(b: conversation_bubble) -> void:
	_layout_side(b.side == conversation_bubble.Side.MINE)


## 摆左还是摆右。编辑器预览也走这条，所以只吃一个 bool，不碰气泡数据。
func _layout_side(mine: bool) -> void:
	%row.alignment = BoxContainer.ALIGNMENT_BEGIN if mine else BoxContainer.ALIGNMENT_END
	%row.move_child(%avatar_frame, 0 if mine else %row.get_child_count() - 1)

	var shrink := Control.SIZE_SHRINK_BEGIN if mine else Control.SIZE_SHRINK_END
	%avatar_frame.size_flags_horizontal = shrink

	if not %avatar_frame.visible:
		# 没头像就没有「靠向说话人那一侧」可言：文字撑满底板并居中。
		# 不这么做的话，text_box 那 600px 会缩在底板的一头，另一头空一大片
		# ——提示气泡（notice_dialog）就是这种没头像的用法。
		%text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		%text_box.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return

	%text_box.size_flags_horizontal = shrink
	# 文字也跟着靠同一侧。text_box 有固定的最小宽度（靠它来决定在哪换行），
	# 不翻对齐的话，对方说短句时文字会甩到离头像很远的另一头。
	%text_box.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_LEFT if mine else HORIZONTAL_ALIGNMENT_RIGHT
	)


func _apply_avatar(b: conversation_bubble) -> void:
	var tex: Texture2D = b.avatar if b.avatar != null else default_avatar
	# 没头像就把框也收掉：留个空框比没有更难看，
	# 而且提示气泡本来就不该有说话人的脸。
	%avatar_frame.visible = tex != null
	if tex != null:
		%avatar.texture = tex
