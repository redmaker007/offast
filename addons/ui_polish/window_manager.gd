extends Node

## 窗口排队器（autoload）：保证同一个场景里同一时刻只有一个 popup_window 开着，
## 并且旧窗口的关闭动画播完之后，新窗口才开始弹出。
##
## 没有它的话，两个窗口会在同一帧一个 show 一个 hide；一旦加上动画，
## 中间那 0.1~0.2 秒里两个窗口同时可见，在 VBoxContainer 里还会被排成上下两个。
##
## 状态按场景根分开存。SceneTransition 会把切走的场景挂起而不是销毁，
## 里面的窗口还活着——如果只有一份全局状态，菜单里开个设置面板就会去
## close() 挂起场景里那个隐藏的游戏窗口，把它的状态搞乱。
## 场景根用 popup_window 的 owner（存在场景里的节点，owner 就是场景根）。
##
## 用法（窗口自己不要互相 close）：
##     WindowManager.open_window(self)
##     WindowManager.close_current(scene_root)
##     WindowManager.popup_state_changed.connect(func(root, has_window): ...)  # 比如暂停/恢复游戏

## 某个 scene_root 下"有没有窗口开着"发生翻转时发出（一轮 open/close 链只会各发一次，
## 中途换窗口不会重复触发）。用来把"开/关弹窗"和"暂停/恢复游戏"这类跟着走的状态
## 集中钩在一处，不用在每个窗口脚本里各自散着写。
signal popup_state_changed(scene_root: Node, has_window: bool)

## scene_root -> {"current": popup_window, "target": popup_window, "running": bool, "has_popup": bool}
##   current：当前开着（或正在弹出）的窗口
##   target ：期望的最终状态，null 表示全关。切换途中又来新请求时只改这个值，
##            由正在跑的那一轮自己去看，不会起第二轮。
##   has_popup：上一次发出的 popup_state_changed 是 true 还是 false，避免同一轮里
##              连续换好几个窗口时，每次换窗口都误发一次"没有弹窗了"。
var _states: Dictionary = {}


## 打开指定窗口，会先把同场景里当前开着的窗口关掉。已经开着的窗口重复调用是空操作。
func open_window(w: popup_window) -> void:
	if not is_instance_valid(w):
		return
	var root := scene_root_of(w)
	await _request(root, _state_for(root), w)


## 关掉指定场景当前开着的窗口。
func close_current(scene_root: Node) -> void:
	await _request(scene_root, _state_for(scene_root), null)


## 指定场景当前开着的窗口，没有就是 null。
func get_current(scene_root: Node) -> popup_window:
	var st := _state_for(scene_root)
	if not is_instance_valid(st["current"]):
		st["current"] = null
	return st["current"]


## 让管理器接管"场景里一开始就是显示状态"的窗口。
## 由 popup_window._ready() 自己调用，不然管理器不知道有窗口开着，
## 下一次 open_window 就不会去关它。
func adopt(w: popup_window) -> void:
	var root := scene_root_of(w)
	var st := _state_for(root)
	if is_instance_valid(st["current"]) and st["current"] != w:
		push_warning("场景 %s 里同时有多个窗口一开始就是显示状态：%s / %s"
			% [root.name, st["current"].name, w.name])
	st["current"] = w


## 窗口属于哪个场景。存在场景里的节点 owner 就是场景根；
## 运行时 add_child 出来的窗口没有 owner，就拿它自己当一档。
func scene_root_of(w: Node) -> Node:
	return w.owner if w.owner != null else w


func _state_for(root: Node) -> Dictionary:
	_prune()
	if not _states.has(root):
		_states[root] = {"current": null, "target": null, "running": false, "has_popup": false}
	return _states[root]


## 场景被销毁之后把它那份状态也丢掉，免得字典无限长。
func _prune() -> void:
	for root in _states.keys():
		if not is_instance_valid(root):
			_states.erase(root)


func _request(root: Node, st: Dictionary, w: popup_window) -> void:
	st["target"] = w
	if st["running"]:
		# 正在跑的那一轮结束前会重新读 target，这里直接搭车就行。
		return
	st["running"] = true
	await _run(root, st)
	st["running"] = false


func _run(root: Node, st: Dictionary) -> void:
	# 每次只走一步（关一个 / 开一个），走完回到循环顶上重新判断，
	# 这样动画期间进来的新请求能立刻接上，不会排成一长串。
	while true:
		if not is_instance_valid(st["current"]):
			st["current"] = null

		if st["current"] != null:
			if st["current"] == st["target"]:
				return
			await st["current"].close()
			st["current"] = null

		if st["target"] == null or not is_instance_valid(st["target"]):
			st["target"] = null
			if st["has_popup"]:
				st["has_popup"] = false
				popup_state_changed.emit(root, false)
			return

		if not st["has_popup"]:
			st["has_popup"] = true
			popup_state_changed.emit(root, true)
		st["current"] = st["target"]
		await st["current"].open()
