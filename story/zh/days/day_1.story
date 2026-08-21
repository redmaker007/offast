# 第 1 天：入职。学会看邮件、填人事表。
# 电脑账号密码印在桌上那本记事本第 1 页。
# 鲍勃第一次出现——他的申请不算对错，只影响结局分。

[day]
filler: 4
roster: Bob

[story]
them: 第一天。
them: 你拿到了这份工作。看邮件，照着做。
them: 读过的邮件会被系统删掉。公司规定。
them!: 电脑要登录。上一个坐这儿的人，在桌上留了本子。

[mail day1_roderick from="罗德里克" faction=B graded=no about=Roderick]
subject: 很高兴认识你！
新上任的人事部组长！我是 Offast 的项目部总经理。
有任何需要帮助的地方，别吝啬向我求助！

[mail day1_mira from="米拉" faction=GROUND graded=no about=Mira]
subject: 祝贺
你好，新来的人事部组长。祝贺你的到来。
祝你好运。

[mail day1_bob from="鲍勃" faction=GROUND graded=no about=Bob]
subject: 加薪申请
您好，我想申请加薪。
我在公司五年了，一直没有出过差错。
谢谢您抽时间看。

[caller]
them: 电话响了两声，停了。又响一声。
them: "前台。给新工位测一下线路。听得见吗？"
me: 听得见。
them: "好。回头会有人找你。" 咔哒。

[score]
if did(raise,Bob) and did(promotion,Bob) -> D+1
if "did(raise,Bob) and not did(promotion,Bob)" -> C+1
