extends Resource
class_name employee_profile

## 一个剧情角色的人事档案。随机员工没有档案（90 个随机名字都配上生成文本，
## 只会把真正重要的几个人淹掉）。
##
## 可见与否只看一件事：**当前登录账户的 clearance >= 这份档案的 clearance**。
## 查不到的人不会灰着显示，而是根本不出现在名单里——「这个号查不到这个人」
## 本身就是信息。

## 员工的**标识**，邮件、人事表、条件（did/level）里用的都是它。
## **不翻译**：换语言时存档里的日志和权限都是按这个键记的，翻了就对不上。
@export var employee_name: StringName = &""

## 给玩家看的名字，跟着语言走（zh 里写「鲍勃」，en 里写 "Bob"）。留空就显示标识。
@export var display_name: String = ""


## 表上、档案页上显示的名字。
func label() -> String:
	return display_name if not display_name.is_empty() else String(employee_name)

@export var position: String = ""
@export var department: String = ""

## 这个人和哪一派走得近。
@export var employee_faction := faction.Id.NONE

@export var avatar: Texture2D

## 要看到这份档案，账户至少得是几级。
@export_range(0, 9) var clearance: int = 0

@export_multiline var body: String = ""
