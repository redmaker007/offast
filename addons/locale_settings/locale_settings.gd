extends Node

## 语言设置（autoload `LocaleSettings`）。
##
## 和音量一样存在 `user://settings.cfg`（`[locale]` 段），**不进游戏存档**——
## 换语言、删档、开新局互不影响。两边写的是同一个文件，`save()` 会先 load 再写，
## 不会把对方那一段冲掉。
##
## 语言影响两样东西：
##   1. UI 文字（`tr()` / Control 的自动翻译，表在 locale/ui.csv）
##   2. 剧情内容（story/<locale>/ 一整套 .story，由 story_book 按语言装）
## 所以切语言时要发 locale_changed，story_book 收到就重装内容。

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "locale"

## 支持的语言，顺序就是设置面板里循环的顺序。
const SUPPORTED := ["zh", "en"]

## 设置面板上显示的名字。用各自的语言写，玩家看得懂自己要选哪个。
const LABELS := {
	"zh": "中文",
	"en": "English",
}

const DEFAULT := "zh"

## GM 模式：开着时放出测试用的东西和可视化剧情编辑器。功能还没接，现在只是个开关。
@export var gm_mode: bool = false

var current := DEFAULT


func _ready() -> void:
	load_settings()


## 切语言。save 传 false 只切不存（预览用）。
func set_locale(loc: String, save := true) -> void:
	var target := loc if loc in SUPPORTED else DEFAULT
	current = target
	TranslationServer.set_locale(target)
	SignalBus.locale_changed.emit(target)
	if save:
		save_settings()


## 循环到下一个语言。设置面板上那个按钮按一下就走这里。
func next_locale() -> void:
	var at := SUPPORTED.find(current)
	set_locale(SUPPORTED[(at + 1) % SUPPORTED.size()])


func label_of(loc := "") -> String:
	var key := loc if not loc.is_empty() else current
	return str(LABELS.get(key, key))


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		set_locale(DEFAULT, false)
		return
	set_locale(str(config.get_value(SECTION, "locale", DEFAULT)), false)


func save_settings() -> void:
	var config := ConfigFile.new()
	# 先 load 再写：音量那一段是别人的，不能被覆盖掉。
	config.load(CONFIG_PATH)
	config.set_value(SECTION, "locale", current)
	config.save(CONFIG_PATH)
