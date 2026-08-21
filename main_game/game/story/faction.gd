extends RefCounted
class_name faction

## 派系的唯一定义处。数值、邮件、档案、日志全都引这里，别再各写一份字符串。
##
## Inspector 里选的是枚举（有下拉框），存档和 GameState 里用的是 StringName——
## 枚举是 int，改动枚举顺序会把旧存档里的派系全对错位，字符串不会。

enum Id {
	NONE,    ## 公司例行公事，不代表任何一方
	A,       ## A 派：威胁型
	B,       ## B 派：表面仁义型
	GROUND,  ## 底层员工
}

const KEY_A := &"A"
const KEY_B := &"B"
const KEY_GROUND := &"GROUND"
const KEY_NONE := &""

## 枚举 → 存档用的键。NONE 是空串，判断「有没有派系」直接看 is_empty()。
static func key(id: int) -> StringName:
	match id:
		Id.A:
			return KEY_A
		Id.B:
			return KEY_B
		Id.GROUND:
			return KEY_GROUND
	return KEY_NONE


## 键 → 给玩家看的名字。日志页用。
static func display(k: StringName) -> String:
	match k:
		KEY_A:
			return TranslationServer.translate("UI_FACTION_A")
		KEY_B:
			return TranslationServer.translate("UI_FACTION_B")
		KEY_GROUND:
			return TranslationServer.translate("UI_FACTION_GROUND")
	return TranslationServer.translate("UI_FACTION_NONE")
