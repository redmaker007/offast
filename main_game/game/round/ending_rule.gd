extends Resource
class_name ending_rule

## 一条结局判定规则：条件成立就走这个结局。
##
## 规则**按写的顺序判，第一条成立的算数**，所以顺序就是设计稿里那张优先级表：
##
##     [ending]
##     if "leading(A) and did(promotion,瑞克,day5)" -> A
##     if leading(A) -> E        # 倒向 A 却没照做最后那封 = 两边都得罪光
##     ...
##
## 都不成立就是兜底结局 C（两派维持制衡）。

@export var condition: String = ""

## 走哪个结局：A / B / C / D / E。
@export var ending: StringName = &"C"
