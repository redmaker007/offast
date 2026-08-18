extends Node

## 全局信号总线。数据层和 UI 层只通过这里对话，互相不持有引用。


# ── 邮件 ────────────────────────────────────────────────

## 发出一封邮件。收件箱和 instruction_box 都听这个。
##
## 标准答案必须建立在「发出去的邮件」而不是「玩家读过的邮件」上——
## 挂钩到已读的话，一封不读直接下班反而全对，不做事成了最优解。
signal send_email(e:email)

## 要显示的邮件（UI 侧）。只有邮件页听，重发是安全的。
signal show_email(e:email)

## 收件箱空了。邮件页据此显示「没有新邮件」。
## 邮件阅后即焚，所以这不代表今天的活干完了，也不推进任何状态。
signal inbox_empty()


# ── 一天的三段流转 ───────────────────────────────────────

signal round_state_change(rs:RoundState.Round_State)

## 这一天的剧情播完了，可以开始上班。
signal story_finished()

## 上班时钟走了一格。clock_text 形如 "13:20"，ratio 是 0→1 的进度。
signal day_time_changed(clock_text:String, ratio:float)

## 到点了，强制下班。
signal day_time_up()

## 玩家自己点门提前下班。活没干完的话会被 round_manager 挡下来，
## 挡下来时发 notice_requested 说明原因。
signal leave_office_request()

## 弹一条只有「知道了」一个选项的提示。谁都能发，notice_dialog 负责显示。
## 提示是模态的：盖住整个屏幕，关掉之前点不了别的。
signal notice_requested(text:String)

## 当天判分结果出来了，结算层据此显示。
signal day_result_ready(result:Dictionary)

## 玩家在结算层点了继续。
signal result_confirmed()

## 扣了一条命，remaining 是扣完之后还剩几条。
signal life_lost(remaining:int)

## 三条命掉光，主角被开除。
signal game_over()

## 扛过了最后一天。
signal game_cleared()


# ── 存档 ────────────────────────────────────────────────

## 存档已经灌回各个节点，UI 该按恢复出来的数据重绘一遍了。
## round_state_change 不能拿来干这个——它会连带触发发邮件之类的数据副作用。
signal game_restored()


# ── 笔记本窗口 ───────────────────────────────────────────

## 玩家点了桌面上的笔记本，请求打开笔记本窗口。
## 打开后固定落在选择页，再由玩家自己翻到别的页。
signal open_laptop_request()

## 笔记本选择页上点了「邮件」，请求翻到邮件页。
signal open_email_page_request()

## 笔记本选择页上点了「人事」，请求翻到人员调动页。
signal open_instruction_page_request()


# ── 其它桌面 / 墙面物件 ──────────────────────────────────
## 都由挂在物件上的 clickable_item 发出。部分还没有接收方，
## 点了不会有反应但也不会报错（clickable_item 会先查 has_signal）。

## 玩家点了电话，请求打开来电界面。
signal open_caller_request()

## 玩家点了日历，请求打开日历界面（看剩几条命、第几天）。
signal open_calendar_request()

## 玩家点了电箱，请求打开电箱界面。
signal open_electricbox_request()

## 玩家点了便签，请求打开便签界面。
signal open_notes_request()

## 玩家点了灯，请求打开灯的界面。
signal open_light_request()
