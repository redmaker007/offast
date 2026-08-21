extends Resource
class_name account

## 一个系统账户。玩家在笔记本的登录页真的把用户名和密码敲进去，
## 所以密码是剧情道具——写在便签上、藏在邮件里，玩家自己记住。
##
## clearance 决定这个号能查到哪些员工档案（账号等级 >= 档案等级就整份可见）。
## 后面几天推进剧情的主要方式就是拿到等级更高的号。

@export var username: StringName = &""
@export var password: String = ""

## 登录后显示的名字，比如 "Temp HR"。
@export var display_name: String = ""

@export_range(0, 9) var clearance: int = 0


func matches(user: String, secret: String) -> bool:
	# 用户名不区分大小写、去掉首尾空格；密码严格匹配。
	return String(username).to_lower() == user.strip_edges().to_lower() and password == secret
