extends Resource
class_name account

## 一个系统账户。玩家在笔记本的登录页真的把用户名和密码敲进去，
## 所以密码是剧情道具——写在便签上、藏在邮件里，玩家自己记住。
##
## clearance 决定这个号能查到哪些员工档案（账号等级 >= 档案等级就整份可见）。
## 后面几天推进剧情的主要方式就是拿到等级更高的号。

@export var username: StringName = &""

## 写死的密码。**留空 = 每局随机 4 位**（和电话号码一个道理：防止玩家背密码）。
## 这一局真正生效的密码问 `GameState.account_password(username)`，别直接读这个字段。
@export var fixed_password: String = ""

## 登录后显示的名字，比如 "Temp HR"。
@export var display_name: String = ""

@export_range(0, 9) var clearance: int = 0


## 用户名对不对（不区分大小写、去掉首尾空格）。
##
## **密码不在这里比**：这一局的密码可能是随机摇出来的，只有 GameState 知道，
## 而这个资源是 .story 导入产物、编辑器里也会加载，碰不到 autoload。
## 完整的校验走 `story_book.account_for()`。
func matches_user(user: String) -> bool:
	return String(username).to_lower() == user.strip_edges().to_lower()
