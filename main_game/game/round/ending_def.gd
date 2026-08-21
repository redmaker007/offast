extends Resource
class_name ending_def

## 一个结局：先播一段对话（可留空），再落到结局卡上。
##
## 文案写在内容文件（world.story 的 [ending_text A] 块）里，跟着语言走。

## 哪个结局：A / B / C / D / E。
@export var ending_id: StringName = &""

## 结局卡上的大字。
@export var title: String = ""

## 结局卡上的正文。
@export_multiline var body: String = ""

## 结局卡之前播的那段剧情。留空就直接出卡。
@export var story: conversation
