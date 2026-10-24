extends RefCounted
class_name level_error

## 一条校验错误：代码 + 参数 + 位置。存结构而不是存句子，
## 编辑器要按位置标红、测试要按代码断言、显示时才翻成当前语言的文字。
##
## 代码表见 docs/level_engine.md 第 8 节。

## 文字模板。显示时先找翻译 key LEVEL_ERR_<代码>，没有才用这里的中文。
## {xxx} 换成 params 里同名的值；{node} / {day} 换成位置。
const TEMPLATES := {
	"LOAD_FAILED": "关卡文件读不进来：{detail}",
	"START_COUNT": "初始天节点要恰好一个，现在有 {count} 个",
	"NO_ENDING": "至少要有一个结局天节点",
	"UNREACHABLE": "{node} 从入口走不到（孤立节点）",
	"NO_PATH_TO_END": "{node} 走不到任何结局，会被困住",
	"ENDING_HAS_EXIT": "结局天 {node} 不能有出口",
	"BAD_ROLE": "{node} 的 role「{role}」不认识（只能是 start / normal / ending）",
	"BAD_JUMP_MODE": "{node} 的 mode「{mode}」不认识（只能是 set / add）",
	"FIRED_ENDING_MISSING": "背景设定里没填被开除时去哪个结局",
	"FIRED_ENDING_NOT_ENDING": "被开除时要去的「{target}」不是结局天节点",
	"LIVES_INVALID": "命数 {value} 不在允许的选项里（{options}）",
	"DUP_VARIABLE": "变量 {id} 定义了不止一次",
	"UNKNOWN_VARIABLE": "{node} 用到了没定义的变量 {id}",
	"DUP_WORLD_ID": "世界表 {table} 里 id {id} 重复",
	"UNKNOWN_OBJECT": "{node} 引用了不存在的房间物件「{object}」",
	"UNKNOWN_TYPE": "{node} 的类型「{type}」不认识",
	"UNKNOWN_PORT": "{node} 没有叫「{port}」的出口",
	"PORT_MISSING": "{node} 的出口「{port}」必须接上",
	"TOO_MANY_TARGETS": "{node} 的出口「{port}」只能接一个节点",
	"BAD_TARGET": "{node} 的出口「{port}」接到了不存在的节点「{target}」",
	"WRONG_TARGET_TYPE": "{node} 的出口「{port}」不能接到 {target}（类型 {target_type}）",
	"BAD_CONDITION": "{node} 的条件写错了：{detail}",
	"DAY_BODY_MISSING": "天节点 {node} 里面没有天内图",
	"BAD_LAYER": "{node} 的 layer「{layer}」不认识（只能是 notice / story / event）",
	"BAD_SCRIPT": "{node} 的文字（{locale}）写错了：{detail}",
	"DUP_MAIL_ID": "{node} 里的邮件 id {id} 和 {other} 重复了",
	"DAY_START_COUNT": "天内图要恰好一个开始节点，现在有 {count} 个",
	"DAY_NO_END": "天内图走不到「天结束」节点",
	"CHAIN_LOOP": "强制链从 {node} 绕回了自己，永远回不到自由环节",
	"NOT_LISTENED": "可互动物件 {node} 没有接在任何自由环节的 listen 上",
}

var code: String = ""
var params: Dictionary = {}

## 出错的天节点 id。外层错误为空。
var day: String = ""

## 出错的节点 id。整份关卡的错误（比如没有结局）为空。
var node: String = ""


func _init(p_code := "", p_params := {}, p_day := "", p_node := "") -> void:
	code = p_code
	params = p_params
	day = p_day
	node = p_node


## 「第几天里的哪个节点」，报错和编辑器跳转用。
func location() -> String:
	if day.is_empty():
		return node
	if node.is_empty():
		return day
	return "%s/%s" % [day, node]


## 转成给人看的一句话（当前语言）。
func describe() -> String:
	var key := "LEVEL_ERR_" + code
	var template := tr(key)
	if template == key:
		template = TEMPLATES.get(code, code)
	var values := params.duplicate()
	values["node"] = node
	values["day"] = day
	var text := template.format(values)
	return text if day.is_empty() else "[%s] %s" % [day, text]


func _to_string() -> String:
	return "%s @ %s %s" % [code, location(), params]
