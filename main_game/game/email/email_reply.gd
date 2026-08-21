extends Resource
class_name email_reply

## 一条回复选项。正式邮件和内部私信共用——两边玩家做的事是一样的：
## 从两三条措辞里挑一条，措辞不同暗示的立场不同。

## 按钮上显示的字。
@export_multiline var text: String = ""

## 选了之后发生什么（立场增量 / 剧情开关 / 档案解锁 / 回显）。
@export var effect: story_effect
