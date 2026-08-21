extends Resource
class_name story_text_block

## 一段带条件的文字。邮件正文和档案正文都是由若干段拼出来的：
## 没写条件的段总是显示，`?if ...` / `?end` 之间的段只在条件成立时显示。
##
## 这样第三天鲍勃那封信才能「给过他 promotion 就多说一句谢谢」，
## 而不用为每种情况各写一封信。

## 留空 = 无条件显示。语法见 story_condition。
@export var condition: String = ""

@export_multiline var text: String = ""


func visible() -> bool:
	return story_condition.eval(condition)
