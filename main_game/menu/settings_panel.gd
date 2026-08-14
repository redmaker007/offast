extends popup_window

## 设置面板（占位）。开关动画全部来自 popup_window，这里只处理关闭按钮。
##
## 关闭要走 WindowManager 而不是直接 close()：管理器记着"这个场景当前开着谁"，
## 绕过它直接关掉的话，下次 open_window() 会以为面板还开着，直接跳过不弹。


func _on_close_pressed() -> void:
	WindowManager.close_current(owner)
