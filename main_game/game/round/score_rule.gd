extends Resource
class_name score_rule

## 日终结算的一条规则：条件成立就应用一个 story_effect。
##
## 对应设计稿里每天末尾那串「逻辑项」：
##     如果 fire 掉今日所有员工 → 结局A+2
##     如果一个员工都没有 fire → 结局C+2
##
## 在 .story 里写成：
##     [score]
##     if did(fire,*random) -> A+2
##     if not did(fire,*any) -> C+2
##
## 规则按写的顺序判，互不排斥——条件都成立就都加。

@export var condition: String = ""

@export var effect: story_effect
