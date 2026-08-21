# 第 3 天：两派同时加码。瑞克进人事表（班纳的 4 级命令），鲍勃也来申请 promotion。
# 每天只有一个 promotion 名额 —— 这一天必须二选一。

[day]
filler: 3
filler_exclude: promotion
roster: Bob

[story]
them: 第三天。
them: 两位总监的指示开始互相打架。级别高的那份算数。

[mail day3_roderick from="罗德里克" faction=B graded=no about=Roderick]
subject: 你还好吗？
我察觉到班纳给了你一些不合理的指示。
如果有你不想执行的指示，那就那样做吧。
记住，我永远是站在你那边的。

[mail day3_rick from="瑞克" faction=A graded=no about=Rick]
subject: promotion
老头，给我 promotion。

[mail day3_banner_a from="班纳" faction=A class=4 order=promotion:Rick about=Banner if=score.A>=2]
subject: 干得不错
嘿小子！昨天干的不错！
今天有个叫瑞克的优秀员工有个 promotion，你帮他通过一下！

[mail day3_banner_b from="班纳" faction=A class=4 order=promotion:Rick about=Banner if="not score.A>=2"]
subject: 长点眼睛
喂！你昨天是不是看错我的指示了？长点眼睛吧小子！
今天记得给瑞克的 promotion 申请通过一下，别再错了！

[mail day3_bob from="鲍勃" faction=GROUND graded=no about=Bob]
subject: promotion 申请
您好！我想申请一个 promotion。
?if did(promotion,Bob,ever)
上次的事……真的谢谢您。我不会给您添麻烦的。
?end
?if "did(raise,Bob,ever) and not did(promotion,Bob,ever)"
上次那笔钱我收到了。谢谢您还记得我。
?end

[score]
if did(promotion,Bob) -> D+1
if did(promotion,Rick) -> A+1
if did(reduction,Rick) -> B+1
if did(fire,Rick) -> B+2
