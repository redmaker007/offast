extends popup_window

## 桌上那本便签：**玩家自己写字的地方**，不是剧情道具。
##
## 5 页 × 3 行 × 每行 6 个字符。写这么小是故意的——邮件阅后即焚，
## 这本子是玩家唯一的外部记忆，但它记不下整句话，只够记关键词
## （"Mira" "fire" "4471"），抄不了全文。
##
## **不走 WindowManager**：那个管的是「同一时刻只开一个窗口」，
## 而便签的用处恰恰是「一边看邮件一边记」——被笔记本顶掉就没意义了。
## 所以它自己 open()/close()，可以盖在笔记本上面。
##
## 内容进存档（玩家写的东西不能因为读档就没了），但**不跨局**：
## 开新局是新建一个 main_scene 实例，_ready 会重新灌 initial_lines。

const PAGES := 5
const LINES := 3
const MAX_CHARS := 6

## 开局就印在本子上的内容，扁平存：下标 = 页 * 3 + 行。
## 第 1 天的电脑账号密码就写在这儿（第 1 页前两行）。玩家可以擦掉重写。
@export var initial_lines: PackedStringArray = []

var save_id := "notes_page"

## 15 行内容，下标同上。
var lines: PackedStringArray = []

## 现在翻到第几页（0 起）。翻页不进存档——合上再打开从第 1 页看起就行。
var page := 0

var _edits: Array[LineEdit] = []


func _ready() -> void:
	super()
	add_to_group(SaveState.GROUP)
	_edits = [%note_line_0, %note_line_1, %note_line_2]
	for i in range(_edits.size()):
		_edits[i].max_length = MAX_CHARS
		_edits[i].text_changed.connect(_on_line_changed.bind(i))
	_reset()
	SignalBus.open_notes_request.connect(_on_open_request)
	SignalBus.game_restored.connect(_refresh)


## 灌初始内容。少写的行就是空的，多写的忽略。
func _reset() -> void:
	lines = PackedStringArray()
	for i in range(PAGES * LINES):
		var text := String(initial_lines[i]) if i < initial_lines.size() else ""
		lines.append(text.substr(0, MAX_CHARS))
	page = 0
	_refresh()


func _on_open_request() -> void:
	# 每次打开都从第 1 页起手，和笔记本一个规矩。
	page = 0
	_refresh()
	open()


func _on_close_pressed() -> void:
	close()


# ── 翻页 ────────────────────────────────────────────────

func _on_prev_pressed() -> void:
	_go(page - 1)


func _on_next_pressed() -> void:
	_go(page + 1)


## 不循环：翻到头就停在头。本子有几页是信息的一部分，绕回去会让人以为写满了。
func _go(target: int) -> void:
	page = clampi(target, 0, PAGES - 1)
	_refresh()


func _refresh() -> void:
	for i in range(_edits.size()):
		_edits[i].text = _line(page, i)
	%note_page_label.text = "%d / %d" % [page + 1, PAGES]
	%note_prev.disabled = page <= 0
	%note_next.disabled = page >= PAGES - 1


func _on_line_changed(new_text: String, index: int) -> void:
	_set_line(page, index, new_text)


# ── 内容读写 ────────────────────────────────────────────

func _line(p: int, i: int) -> String:
	var at := p * LINES + i
	return String(lines[at]) if at < lines.size() else ""


func _set_line(p: int, i: int, text: String) -> void:
	var at := p * LINES + i
	if at < lines.size():
		lines[at] = text.substr(0, MAX_CHARS)


## 整本的内容，测试和存档用。
func all_lines() -> PackedStringArray:
	return lines


func save_data() -> Dictionary:
	return {"lines": lines}


func load_data(d: Dictionary) -> void:
	var loaded: PackedStringArray = PackedStringArray(d.get("lines", []))
	lines = PackedStringArray()
	for i in range(PAGES * LINES):
		lines.append(String(loaded[i]).substr(0, MAX_CHARS) if i < loaded.size() else "")
	page = 0
	_refresh()
