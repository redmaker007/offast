extends Resource
class_name roster_rule

## 「条件成立才上人事表」的一个角色。
##
## 无条件进表的写在 day_plan.story_roster 里；这个是给「今天到底提没提到他」
## 会变的角色用的。在 .story 里写成：
##
##     [day]
##     roster: Bob
##     roster: me if=did(fire,Rick,day3)
##
## 第四天的主角自己就是这么来的：只有罗德里克那封「你也该为自己想想」真的发出去，
## 表上才有你自己这一行；没人提起过的话，给自己批 promotion 根本不该是个选项。

@export var employee_name: StringName = &""

## 条件（语法见 story_condition）。留空 = 无条件，那还不如写进 story_roster。
@export var condition: String = ""
