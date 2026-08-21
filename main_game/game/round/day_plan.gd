extends Resource
class_name day_plan

## 一天的全部脚本内容：开场剧情、剧情邮件、桌面桥段、强制点名的角色。
##
## **这个资源是 story/days/day_N.story 导入出来的，不手写、不手改。**
## 加一天 = 加一个 .story 文本文件再挂到 story_book 上。
## 每一格都可以留空，留空就退回原来的随机玩法（这也是为什么第 2-5 天
## 现在还没内容也能照常玩）。

@export_group("开场")

## 这一天的开场剧情。**留空则回退 story_page 自己那份 by_day / fallback**。
@export var story: conversation

@export_group("邮件")

## 当天的剧情信，按顺序先发。
@export var scripted_emails: Array[email_def] = []

## 随机填充信的数量。-1 = 用 round_manager.emails_per_day 那个默认值。
@export var filler_emails: int = -1

## 随机信不许出现的指令（写 fire / raise / promotion / reduction）。
## 第三天要用：那天的 promotion 名额得留给剧情角色。
@export var filler_exclude: Array[StringName] = []

@export_group("人事")

## 强制进当天人事表的剧情角色。剧情信点名谁，这里就写谁——
## 不写的话玩家的表上没有这一行，收到命令也没处填。
@export var story_roster: Array[StringName] = []

@export_group("日终结算")

## 当天的「逻辑项」：条件成立就加对应的结局分。按写的顺序判，互不排斥。
@export var score_rules: Array[score_rule] = []

@export_group("桌面桥段")

## 可以反复播的桥段（`[electricbox repeat=yes]`）。默认每天每个物件只播一次，
## 电箱是例外：没钥匙时点开只看到「锁着」，拿到钥匙当天还得能再开一次。
@export var repeatable_events: Array[StringName] = []

## 点桌上的东西时播的对话。留空 = 点了没反应（和现在一样）。
## 便签不在这里：那本是玩家自己写字的记事本（notes_page），不播对话。
@export var caller: conversation
@export var electricbox: conversation
@export var window: conversation


## 桥段名 -> 对应的对话。event_page 用这个查表，省得写四个 if。
## 这个桥段今天能不能重复播。
func repeats(key: StringName) -> bool:
	return key in repeatable_events


func event_for(key: StringName) -> conversation:
	match key:
		&"caller":
			return caller
		&"electricbox":
			return electricbox
		&"window":
			return window
	return null
