extends Node



signal send_email(e:email)

## 读到一封新邮件（数据侧）。instruction_box 靠它累积指令，
## 所以读档恢复时不能重发这个信号，否则指令会被重复累加。
signal read_a_email(e:email)

## 要显示的邮件（UI 侧）。只有邮件窗口听，重发是安全的。
signal show_email(e:email)

signal all_email_read

signal start_to_execute_instruction()

signal all_question_answered()

## 要显示的下一道题。数据层只管发题目文本，具体显示在哪个 Label 由 UI 自己决定。
signal show_question(question_text:String)

signal round_state_change(rs:RoundState.Round_State)

## 存档已经灌回各个节点，UI 该按恢复出来的数据重绘一遍了。
## round_state_change 不能拿来干这个——它会连带触发发邮件之类的数据副作用。
signal game_restored()

signal close_current_window_request()

signal open_email_window_request()
