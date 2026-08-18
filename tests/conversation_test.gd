extends Node

## 对话系统的自测。跑法见 tests/run_tests.ps1。
##
## 覆盖：数据类的取值和跳转、bubble_view 的逐字机 / can_skip / 两种模式切换、
## story_page 把一整段 conversation 播完并发 story_finished、选项分支、按天查表。

const MAIN_SCENE := "res://main_game/game/main_scene.tscn"
const BUBBLE_VIEW := "res://main_game/game/story/bubble_view.tscn"
const CONV_DIR := "res://main_game/game/story/conversations"

var _passed := 0
var _failed := 0
var _fail_lines: Array[String] = []
var _section := ""

var _scene: Node = null
var _story_finished := 0


func _ready() -> void:
	SignalBus.story_finished.connect(func() -> void: _story_finished += 1)

	_test_data_classes()
	_test_shipped_conversations()
	await _test_bubble_typewriter()
	await _test_bubble_cannot_skip()
	await _test_bubble_choice_mode()
	await _test_type_sound()
	await _test_bubble_avatar()
	await _test_bubble_side()
	await _test_plate_style()
	await _test_story_page_linear()
	await _test_story_page_branch()
	await _test_story_page_day_lookup()
	await _test_story_page_empty()

	await _despawn()
	_report()


# ── 数据类 ──────────────────────────────────────────────

func _test_data_classes() -> void:
	_section = "数据类"
	var a := _bubble("first")
	var b := _bubble("second")
	var seg := _dialogue(&"start", [a, b])
	var other := _dialogue(&"branch", [_bubble("branched")])
	var conv := _conversation([seg, other])

	_eq("第一段", conv.first(), seg)
	_eq("按 id 找", conv.find(&"branch"), other)
	_eq("找不到返回 null", conv.find(&"nope"), null)
	_eq("线性下一段", conv.next_after(seg), other)
	_eq("最后一段没有下一段", conv.next_after(other), null)

	_eq("取第 0 条", seg.bubble_at(0), a)
	_eq("越界返回 null", seg.bubble_at(2), null)
	_eq("负下标返回 null", seg.bubble_at(-1), null)

	_is_false("没选项就不是选择题", a.is_choice())
	_is_false("空 conversation 判定", conv.is_empty())
	_is_true("真空的判定", _conversation([]).is_empty())
	_is_true("只有空段也算空", _conversation([_dialogue(&"x", [])]).is_empty())

	var c := conversation_choice.new()
	_is_false("goto 留空就是不跳", c.jumps())
	c.goto = &"branch"
	_is_true("填了 goto 就是跳", c.jumps())

	var q := _bubble("pick one", true, [c])
	_is_true("有选项就是选择题", q.is_choice())


## 从 story_beat 移植过来的那几份 .tres 要还在、还能读。
func _test_shipped_conversations() -> void:
	_section = "随包的剧情资源"
	for i in range(1, 6):
		var path := "%s/day_%d.tres" % [CONV_DIR, i]
		var c: conversation = load(path)
		_is_true("day_%d 能加载" % i, c != null)
		if c != null:
			_is_false("day_%d 非空" % i, c.is_empty())
	var fb: conversation = load("%s/fallback.tres" % CONV_DIR)
	_is_true("fallback 能加载", fb != null)


# ── bubble_view ─────────────────────────────────────────

func _test_bubble_typewriter() -> void:
	_section = "逐字机"
	var view := _spawn_view(40.0)
	var text := "0123456789"      # 10 个字 / 40cps ≈ 0.25 秒
	view.show_bubble(_bubble(text))
	await _frames(2)

	_is_false("刚开始文字没出完", view.is_text_done())
	_is_true("已经在出字了", view.get_node("%text_box").visible_characters >= 0)
	_is_true("还没出全", view.get_node("%text_box").visible_characters < text.length(),
		"visible_characters=%d" % view.get_node("%text_box").visible_characters)
	# can_skip = true 的气泡，打字途中 next 是能按的——那是「提前出全文」的入口。
	_is_false("打字途中 next 可按", view.get_node("%next_button").disabled)

	await get_tree().create_timer(0.5).timeout
	_is_true("等一会儿出完了", view.is_text_done())
	_eq("文字对得上", view.get_node("%text_box").text, text)
	_is_false("出完之后 next 可按", view.get_node("%next_button").disabled)

	# 出完之后按 next 才是「进下一条」。
	var got := [0]
	view.advance_requested.connect(func() -> void: got[0] += 1)
	view.get_node("%next_button").pressed.emit()
	await _frames(1)
	_eq("按下发了一次 advance", got[0], 1)

	view.queue_free()
	await _frames(2)


func _test_bubble_cannot_skip() -> void:
	_section = "can_skip"
	var view := _spawn_view(10.0)   # 慢一点，好在打字途中操作

	# can_skip = true：打字途中按 next 直接刷全文，但不推进。
	var got := [0]
	view.advance_requested.connect(func() -> void: got[0] += 1)
	var skippable := _bubble("0123456789012345", true)
	view.show_bubble(skippable)
	await _frames(2)
	_is_false("按之前没出完", view.is_text_done())
	view.get_node("%next_button").pressed.emit()
	await _frames(1)
	_is_true("提前按之后出完了", view.is_text_done())
	_eq("提前按不算推进", got[0], 0)
	view.get_node("%next_button").pressed.emit()
	await _frames(1)
	_eq("再按一次才推进", got[0], 1)

	# can_skip = false：按钮是灰的，从代码里硬按也不给跳。
	var locked := _bubble("0123456789012345", false)
	view.show_bubble(locked)
	await _frames(2)
	_is_true("重要剧情的 next 是灰的", view.get_node("%next_button").disabled)
	view.get_node("%next_button").pressed.emit()
	await _frames(1)
	_is_false("硬按也不给提前出全文", view.is_text_done())
	_eq("也没推进", got[0], 1)

	# 等它自己走完就正常了。
	await get_tree().create_timer(2.2).timeout
	_is_true("自己走完了", view.is_text_done())
	_is_false("走完之后 next 解锁", view.get_node("%next_button").disabled)

	view.queue_free()
	await _frames(2)


func _test_bubble_choice_mode() -> void:
	_section = "选择题模式"
	var view := _spawn_view(0.0)    # 0 = 不逐字，一次全出

	var c1 := conversation_choice.new()
	c1.text = "Yes"
	var c2 := conversation_choice.new()
	c2.text = "No"
	c2.goto = &"branch"
	view.show_bubble(_bubble("pick", true, [c1, c2]))
	await _frames(2)

	_is_true("文字直接就出完了", view.is_text_done())
	_is_false("next 收起来了", view.get_node("%next_button").visible)
	_is_true("选项显示出来了", view.get_node("%choice_list").visible)

	var buttons := view.get_node("%choice_list").get_children()
	_eq("选项按钮数", buttons.size(), 2)
	if buttons.size() == 2:
		_eq("第一个按钮文字", buttons[0].text, "Yes")
		_eq("第二个按钮文字", buttons[1].text, "No")

	var picked := []
	view.choice_picked.connect(func(i: int, c: conversation_choice) -> void: picked.append([i, c]))
	buttons[1].pressed.emit()
	await _frames(1)
	_eq("发了一次 choice_picked", picked.size(), 1)
	if picked.size() == 1:
		_eq("选中的下标", picked[0][0], 1)
		_eq("选中的选项", picked[0][1], c2)
	_is_true("选完按钮锁住了", buttons[0].disabled and buttons[1].disabled)

	# 换回普通气泡要能切回文字模式。
	view.show_bubble(_bubble("plain"))
	await _frames(2)
	_is_true("next 又出来了", view.get_node("%next_button").visible)
	_is_false("选项收起来了", view.get_node("%choice_list").visible)
	_eq("旧的选项按钮清掉了", _alive_children(view.get_node("%choice_list")), 0)

	view.queue_free()
	await _frames(2)


func _test_type_sound() -> void:
	_section = "打字音效"
	var view := _spawn_view(0.0)
	await _frames(1)

	_is_true("有音效 player", view._audio != null)
	if view._audio == null:
		view.queue_free()
		return
	_eq("挂在 SFX 总线", view._audio.bus, &"SFX")

	# 没配音效：打完一整条也不该响。
	view.chars_per_second = 500.0
	view.show_bubble(_bubble("no sound here"))
	await get_tree().create_timer(0.3).timeout
	_is_true("文字出完了", view.is_text_done())
	_eq("没配音效就不响", view._audio.stream, null)

	var sfx: AudioStream = load("res://sound/click.mp3")
	view.type_sound = sfx

	# 每个字都响。
	view.sound_every_chars = 1
	view.get_node("%text_box").text = "abc"
	view._since_sound = 0
	view._on_chars_revealed(0, 3)
	_eq("响了之后计数归零", view._since_sound, 0)
	_eq("用的是配的那个音效", view._audio.stream, sfx)

	# 空格不算数。
	view._audio.stream = null
	view.get_node("%text_box").text = "   \n\t"
	view._since_sound = 0
	view._on_chars_revealed(0, 5)
	_eq("空白不推进计数", view._since_sound, 0)
	_eq("空白不响", view._audio.stream, null)

	# 每 3 个字响一次。
	view.sound_every_chars = 3
	view.get_node("%text_box").text = "abcdef"
	view._since_sound = 0
	view._on_chars_revealed(0, 2)
	_eq("才 2 个字还没响", view._since_sound, 2)
	_eq("确实没响", view._audio.stream, null)
	view._on_chars_revealed(2, 3)
	_eq("第 3 个字响了，计数归零", view._since_sound, 0)
	_eq("响的是配的音效", view._audio.stream, sfx)

	# 关掉。
	view.sound_every_chars = 0
	view._audio.stream = null
	view.get_node("%text_box").text = "abcdef"
	view._since_sound = 0
	view._on_chars_revealed(0, 6)
	_eq("设成 0 就不响", view._audio.stream, null)

	view.queue_free()
	await _frames(2)


## 头像：气泡自己的优先，其次 default_avatar，两个都没有就把框收起来
## 并把文字居中——提示气泡（notice_dialog）走的就是这条。
func _test_bubble_avatar() -> void:
	_section = "头像"
	var view := _spawn_view(0.0)
	await _frames(1)
	var frame: Control = view.get_node("%avatar_frame")
	var text_box: Control = view.get_node("%text_box")

	view.show_bubble(_bubble("no avatar"))
	await _frames(1)
	_is_false("都没配就收起头像框", frame.visible)
	_eq("没头像时文字居中", text_box.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER)
	_eq("没头像时文字撑满底板", text_box.size_flags_horizontal, Control.SIZE_EXPAND_FILL)

	var fallback := PlaceholderTexture2D.new()
	view.default_avatar = fallback
	view.show_bubble(_bubble("uses default"))
	await _frames(1)
	_is_true("配了默认头像框就出来", frame.visible)
	_eq("用的是默认头像", view.get_node("%avatar").texture, fallback)

	var own := PlaceholderTexture2D.new()
	var b := _bubble("own avatar")
	b.avatar = own
	view.show_bubble(b)
	await _frames(1)
	_eq("气泡自己的头像优先", view.get_node("%avatar").texture, own)

	view.queue_free()
	await _frames(2)


## 我方在左、对方在右：头像框在 row 里的位置、整行的对齐方向都要跟着翻。
func _test_bubble_side() -> void:
	_section = "左右翻转"
	var view := _spawn_view(0.0)
	await _frames(1)
	var row: HBoxContainer = view.get_node("%row")
	var frame: Control = view.get_node("%avatar_frame")
	var text_box: Control = view.get_node("%text_box")

	var mine := _bubble("mine")
	mine.side = conversation_bubble.Side.MINE
	mine.avatar = PlaceholderTexture2D.new()
	view.show_bubble(mine)
	await _frames(1)
	_eq("我方：头像框排第一个", frame.get_index(), 0)
	_eq("我方：整行靠左", row.alignment, BoxContainer.ALIGNMENT_BEGIN)
	_eq("我方：头像框靠左", frame.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN)
	_eq("我方：文字靠左", text_box.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN)
	_eq("我方：文字左对齐", text_box.horizontal_alignment, HORIZONTAL_ALIGNMENT_LEFT)

	var theirs := _bubble("theirs")
	theirs.side = conversation_bubble.Side.THEIRS
	theirs.avatar = PlaceholderTexture2D.new()
	view.show_bubble(theirs)
	await _frames(1)
	_eq("对方：头像框排最后", frame.get_index(), row.get_child_count() - 1)
	_eq("对方：整行靠右", row.alignment, BoxContainer.ALIGNMENT_END)
	_eq("对方：头像框靠右", frame.size_flags_horizontal, Control.SIZE_SHRINK_END)
	_eq("对方：文字靠右", text_box.size_flags_horizontal, Control.SIZE_SHRINK_END)
	# text_box 有固定最小宽度，不翻对齐的话短句会甩到离头像很远的另一头。
	_eq("对方：文字右对齐", text_box.horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT)

	# 翻回来还要能翻回去。
	view.show_bubble(mine)
	await _frames(1)
	_eq("翻回我方：头像框又排第一个", frame.get_index(), 0)
	_eq("翻回我方：整行又靠左", row.alignment, BoxContainer.ALIGNMENT_BEGIN)

	view.queue_free()
	await _frames(2)


## 底板用的是 StyleBox 不是贴图；没配就用场景里那个，配了才换。
func _test_plate_style() -> void:
	_section = "底板样式"
	var view := _spawn_view(0.0)
	await _frames(1)
	var plate: Control = view.get_node("%plate")

	var scene_style := plate.get_theme_stylebox("panel")
	_is_true("场景里自带底板样式", scene_style != null)
	_is_true("是 StyleBoxFlat", scene_style is StyleBoxFlat)
	# 具体配色由用户在编辑器里调，测试只管「是块有底色、有描边的圆角板」，别把调色板写死。
	if scene_style is StyleBoxFlat:
		var flat := scene_style as StyleBoxFlat
		_is_true("底色不透明", flat.bg_color.a > 0.0)
		_is_true("有描边", flat.border_width_left > 0)
		_is_true("是圆角", flat.corner_radius_top_left > 0)

	var theirs := _bubble("t")
	theirs.side = conversation_bubble.Side.THEIRS
	var mine := _bubble("m")
	mine.side = conversation_bubble.Side.MINE

	# 都没配 → 一直是场景里那个。
	view.show_bubble(mine)
	await _frames(1)
	_eq("没配就用场景里的", plate.get_theme_stylebox("panel"), scene_style)

	# 只给我方配 → 对方不能被我方那张污染。
	var custom := StyleBoxFlat.new()
	custom.bg_color = Color("FFBB7E")
	view.plate_style_mine = custom
	view.show_bubble(mine)
	await _frames(1)
	_eq("我方用配的那张", plate.get_theme_stylebox("panel"), custom)
	view.show_bubble(theirs)
	await _frames(1)
	_eq("对方退回场景里那张", plate.get_theme_stylebox("panel"), scene_style)

	view.queue_free()
	await _frames(2)


# ── story_page ──────────────────────────────────────────

func _test_story_page_linear() -> void:
	_section = "story_page 线性播完"
	await _spawn_scene()
	var page := _page()
	var view := page.get_node("VBoxContainer/bubble_view")
	view.chars_per_second = 0.0     # 测流程，不测打字

	_story_finished = 0
	page.play(_conversation([_dialogue(&"start", [
		_bubble("one"), _bubble("two"), _bubble("three"),
	])]))
	await _frames(2)

	_eq("第一条", view.get_node("%text_box").text, "one")
	_next(view)
	await _frames(2)
	_eq("第二条", view.get_node("%text_box").text, "two")
	_next(view)
	await _frames(2)
	_eq("第三条", view.get_node("%text_box").text, "three")
	_eq("还没播完", _story_finished, 0)
	_next(view)
	await _frames(2)
	_eq("播完发了一次 story_finished", _story_finished, 1)


func _test_story_page_branch() -> void:
	_section = "story_page 选项分支"
	var page := _page()
	var view := page.get_node("VBoxContainer/bubble_view")
	view.chars_per_second = 0.0

	var jump := conversation_choice.new()
	jump.text = "go left"
	jump.goto = &"left"
	var stay := conversation_choice.new()
	stay.text = "go on"       # goto 留空 = 线性继续

	var conv := _conversation([
		_dialogue(&"start", [_bubble("ask", true, [jump, stay]), _bubble("after ask")]),
		_dialogue(&"middle", [_bubble("middle")]),
		_dialogue(&"left", [_bubble("left branch")]),
	])

	# 选了带 goto 的 → 跳到那一段。
	_story_finished = 0
	page.play(conv)
	await _frames(2)
	_eq("先问", view.get_node("%text_box").text, "ask")
	_pick(view, 0)
	await _frames(2)
	_eq("跳到了 left 段", view.get_node("%text_box").text, "left branch")
	_next(view)
	await _frames(2)
	_eq("left 是最后一段，播完", _story_finished, 1)

	# 选了不带 goto 的 → 接着走当前段的下一条。
	_story_finished = 0
	page.play(conv)
	await _frames(2)
	_pick(view, 1)
	await _frames(2)
	_eq("线性继续到同段下一条", view.get_node("%text_box").text, "after ask")
	_next(view)
	await _frames(2)
	_eq("这段走完接下一段", view.get_node("%text_box").text, "middle")

	# goto 写错了不崩，退回线性。
	var broken := conversation_choice.new()
	broken.text = "typo"
	broken.goto = &"no_such_dialogue"
	_story_finished = 0
	page.play(_conversation([_dialogue(&"start", [
		_bubble("q", true, [broken]), _bubble("fallthrough"),
	])]))
	await _frames(2)
	_pick(view, 0)
	await _frames(2)
	_eq("goto 写错退回线性", view.get_node("%text_box").text, "fallthrough")


func _test_story_page_day_lookup() -> void:
	_section = "按天查表"
	var page := _page()
	var d1: conversation = load("%s/day_1.tres" % CONV_DIR)
	var fb: conversation = load("%s/fallback.tres" % CONV_DIR)

	_eq("第 1 天", page.conversation_for_day(1), d1)
	_eq("第 5 天", page.conversation_for_day(5), load("%s/day_5.tres" % CONV_DIR))
	_eq("超出配置的天用 fallback", page.conversation_for_day(99), fb)
	_eq("第 0 天也用 fallback", page.conversation_for_day(0), fb)


func _test_story_page_empty() -> void:
	_section = "没配剧情"
	var page := _page()
	_story_finished = 0
	page.play(null)
	await _frames(2)
	_eq("没剧情直接结束", _story_finished, 1)

	_story_finished = 0
	page.play(_conversation([]))
	await _frames(2)
	_eq("空 conversation 也直接结束", _story_finished, 1)


# ── 造数据 ──────────────────────────────────────────────

func _bubble(text: String, can_skip := true, choices: Array = []) -> conversation_bubble:
	var b := conversation_bubble.new()
	b.text = text
	b.can_skip = can_skip
	var typed: Array[conversation_choice] = []
	for c in choices:
		typed.append(c)
	b.choices = typed
	return b


func _dialogue(id: StringName, bubbles: Array) -> dialogue:
	var d := dialogue.new()
	d.id = id
	var typed: Array[conversation_bubble] = []
	for b in bubbles:
		typed.append(b)
	d.bubbles = typed
	return d


func _conversation(segments: Array) -> conversation:
	var c := conversation.new()
	var typed: Array[dialogue] = []
	for s in segments:
		typed.append(s)
	c.dialogues = typed
	return c


# ── 场景 ────────────────────────────────────────────────

func _spawn_view(cps: float) -> bubble_view:
	var v: bubble_view = (load(BUBBLE_VIEW) as PackedScene).instantiate()
	v.chars_per_second = cps
	add_child(v)
	return v


func _spawn_scene() -> void:
	await _despawn()
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_scene)
	await _frames(3)


func _despawn() -> void:
	if _scene == null:
		return
	var old := _scene
	_scene = null
	remove_child(old)
	old.queue_free()
	await _frames(2)


func _page() -> Node:
	return _scene.get_node("story_page")


func _next(view: Node) -> void:
	view.get_node("%next_button").pressed.emit()


func _pick(view: Node, index: int) -> void:
	var buttons := view.get_node("%choice_list").get_children()
	if index >= 0 and index < buttons.size():
		buttons[index].pressed.emit()


func _alive_children(n: Node) -> int:
	var count := 0
	for c in n.get_children():
		if not c.is_queued_for_deletion():
			count += 1
	return count


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


# ── 断言 ────────────────────────────────────────────────

func _eq(label: String, actual: Variant, expected: Variant) -> void:
	_record(label, actual == expected, "期望 %s，实际 %s" % [str(expected), str(actual)])


func _is_true(label: String, cond: bool, detail := "") -> void:
	_record(label, cond, "期望为真" if detail.is_empty() else detail)


func _is_false(label: String, cond: bool, detail := "") -> void:
	_record(label, not cond, "期望为假" if detail.is_empty() else detail)


func _record(label: String, ok: bool, detail: String) -> void:
	if ok:
		_passed += 1
		return
	_failed += 1
	_fail_lines.append("  ✗ [%s] %s —— %s" % [_section, label, detail])


func _report() -> void:
	print("\n============ conversation_test ============")
	if _failed == 0:
		print("全部通过：%d 项" % _passed)
	else:
		print("通过 %d 项，失败 %d 项：" % [_passed, _failed])
		for line in _fail_lines:
			print(line)
	print("===========================================\n")
	get_tree().quit(1 if _failed > 0 else 0)
