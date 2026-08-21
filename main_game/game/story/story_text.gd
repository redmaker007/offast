extends RefCounted
class_name story_text

## 文本里的占位符替换。现在只有一种：`{caller:米拉}` → 那个人这一局的电话号码。
##
## 号码每局随机（防背点），所以文案里不能写死；邮件、对话、档案显示前
## 都要过一遍这里。还没拿到号码的人显示成 `----`——玩家看到的是
## 「这里本该有个号码」，而不是一段穿帮的占位符。

const UNKNOWN := "----"


## GameState 是 autoload，编辑器里不存在（bubble_view 是 @tool，导入期会走到这儿）。
## 运行期现查，查不到就显示占位。
static func _state() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("GameState")
	return null


static func resolve(text: String) -> String:
	if not text.contains("{caller:"):
		return text
	var out := text
	while true:
		var open_at := out.find("{caller:")
		if open_at < 0:
			break
		var close_at := out.find("}", open_at)
		if close_at < 0:
			break
		var name := out.substr(open_at + 8, close_at - open_at - 8).strip_edges()
		var gs := _state()
		var number: String = gs.caller_number(StringName(name)) if gs != null else ""
		out = out.substr(0, open_at) + (number if not number.is_empty() else UNKNOWN) + out.substr(close_at + 1)
	return out
