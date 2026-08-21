extends Resource
class_name contact

## 一个能打电话的人。号码**每局随机**（防背点），所以文案里一律写
## `{caller:名字}` 占位符，显示时才换成这一局的真号码。
##
## 玩家要把号码抄进桌上那本记事本——一行 6 个字符，所以号码是 4 位数字。

## 内部名，`{caller:X}`、`called(X)` 里写的就是它。
@export var contact_name: StringName = &""

## 接通后显示的名字。留空就用 contact_name。
@export var display_name: String = ""

## 固定号码。**留空 = 每局随机生成 4 位**（大多数联系人都该留空）。
@export var fixed_number: String = ""

## 拨通之后播的那段对话。留空 = 号码存在但没人接。
@export var call: conversation


func label() -> String:
	return display_name if not display_name.is_empty() else String(contact_name)
