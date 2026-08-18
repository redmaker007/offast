extends clickable_item
class_name calendar_face

## 桌上的日历：图案随剩余命数变化，是「还剩几条命」的图画隐喻。
##
## 继承 clickable_item，所以悬停发光和点击开日历页的行为原样保留，
## 这里只多做一件事——按 round_manager.lives 换贴图。
##
## 四个槽在 Inspector 里拖图进去。留空的槽会自动回退到最近的一张，
## 所以只填一两张也不会变成空白日历。

## 满命（3 条）时的日历。
@export var face_3_lives: Texture2D
## 剩 2 条命。
@export var face_2_lives: Texture2D
## 剩 1 条命。
@export var face_1_life: Texture2D
## 命掉光了。
@export var face_0_lives: Texture2D


func _ready() -> void:
	# 父类在这里连了 mouse_entered / mouse_exited / round_state_change，
	# 所以下面不要再连一次 round_state_change——重复连接会让 refresh 跑两遍。
	super()
	SignalBus.life_lost.connect(_on_life_lost)
	SignalBus.game_restored.connect(refresh)
	refresh()


## 覆盖父类的状态回调：先让父类同步发光，再顺手换图。
func _on_round_state_change(rs) -> void:
	super(rs)
	refresh()


func _on_life_lost(_remaining: int) -> void:
	refresh()


## 按当前命数换图。一张都没配就保持场景里原本那张。
func refresh() -> void:
	var face := current_face()
	if face == null:
		return
	# clickable_item 继承的是 Control，静态类型里没有 texture。
	# 这个脚本只会挂在 TextureRect 上，所以用动态赋值。
	set("texture", face)


## 当前命数该显示哪张。日历页也调这个，保证桌面和弹窗永远一致。
func current_face() -> Texture2D:
	var slots: Array[Texture2D] = [face_0_lives, face_1_life, face_2_lives, face_3_lives]
	var idx := clampi(_current_lives(), 0, slots.size() - 1)

	# 对应槽位空着就先往命数更高的方向找一张顶上，再往低处找，避免空白。
	for i in range(idx, slots.size()):
		if slots[i] != null:
			return slots[i]
	for i in range(idx, -1, -1):
		if slots[i] != null:
			return slots[i]
	return null


## 开局前（还没发第一天）round_manager.lives 还是 0，
## 这时候不该显示「已经死透」的那张。
func _current_lives() -> int:
	var rm = %round_manager
	if rm.current_day <= 0:
		return rm.max_lives
	return rm.lives
