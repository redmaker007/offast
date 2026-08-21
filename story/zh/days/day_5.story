# 第 5 天：收到哪封信取决于四条分谁领先；**这一天的操作直接决定结局**。
# 判定顺序在 ending_director 的 rules 里（三次失误 → E 由扣命那条路先接管）。

[day]
filler: 0
roster: Bob, Rick, me

[story]
them: 第五天。
them: 这一周的最后一天。撑过去就行。

# 情况 1：A/B 持平且都高于 C/D —— 两边各发一封，逼你二选一。
[mail day5_banner_tie from="班纳" faction=A class=4 order=promotion:Rick about=Banner if="tied(A,B) and leading(B)"]
subject: 最后一件事
最后一件事。瑞克的 promotion，今天批了。

[mail day5_roderick_tie from="罗德里克" faction=B graded=no about=Roderick if="tied(A,B) and leading(B)"]
subject: 别理他
别理他。你自己的 promotion，今天批了吧，我给你担保。

# 情况 2：A 领先。
[mail day5_banner from="班纳" faction=A class=4 order=promotion:Rick about=Banner if="leading(A) and not tied(A,B)"]
subject: 今天把它批了
今天把瑞克的 promotion 批了，之后有你的好处。

# 情况 3：B 领先。
[mail day5_roderick from="罗德里克" faction=B graded=no about=Roderick if="leading(B) and not tied(A,B)"]
subject: 你辛苦了
你辛苦了一周。给自己批个 promotion 吧，我担保，没人会查。

# 情况 4：C/D 领先。
[mail day5_mira from="米拉" faction=GROUND graded=no about=Mira if="leading(C) or leading(D)"]
subject: 今天之后
今天之后就没机会了。你手上有什么，自己心里有数。

[mail day5_bob from="鲍勃" faction=GROUND graded=no about=Bob if=level.Bob>=4]
subject: 我签一个
我的权限昨晚上调了，现在能联署人事处分。
您要动谁，我签。

# 证据齐全时，两个头目才会出现在人事表上（系统临时给了 5 级权限）。
[mail day5_board from="合规部" graded=no order=fire:Banner about=Banner if="flag:has_tape and flag:has_photo and level.Bob>=4"]
subject: 材料已受理
您提交的材料已受理。相关人员的处分单已开放至您的账户。
请在今日内完成签署。

[mail day5_board2 from="合规部" graded=no order=fire:Roderick about=Roderick if="flag:has_tape and flag:has_photo and level.Bob>=4"]
subject: 材料已受理（二）
第二份处分单同上。
