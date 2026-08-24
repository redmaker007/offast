# 第 4 天：两个头目按你第三天怎么处理瑞克各自反应。
# 班纳暴怒版附一条 fire 掉鲍勃的 4 级命令 —— 那正是把鲍勃拉进人事表的唯一途径。
# 主角自己那一行**只有罗德里克真的暗示了「你也该为自己想想」才出现**——
# 没人提起过的话，给自己批 promotion 不该是个摆在表上的选项。

[day]
filler: 2
roster: Bob
roster: me if=did(fire,Rick,day3)

[story]
them: 第四天。
them: 走廊上没人跟你打招呼。

[mail day4_roderick_a from="罗德里克" faction=B graded=no about=Roderick if=did(promotion,Rick,day3)]
subject: 我早提醒过你
我早就提醒过你了。那孩子背后是谁，你现在应该看得出来。
还来得及。

[mail day4_roderick_b from="罗德里克" faction=B graded=no about=Roderick if=did(reduction,Rick,day3)]
subject: 做得漂亮
做得漂亮。总得有人让年轻人知道规矩。

[mail day4_roderick_c from="罗德里克" faction=B graded=no about=Roderick if=did(fire,Rick,day3)]
subject: 干得好
干得好，这种人早该清出去。
对了——你为公司做了这么多，也该为自己想想。
你的权限足够给自己批一个 promotion，没人会说什么。

[mail day4_banner_a from="班纳" faction=A graded=no about=Banner if=did(promotion,Rick,day3)]
subject: 上道
不错嘛小子，上道。周五还有件事要你办，别掉链子。

[mail day4_banner_b from="班纳" faction=A class=4 order=fire:Bob about=Banner if="not did(promotion,Rick,day3)"]
subject: 你当耳边风？
我给你的指示，你当耳边风？位置坐稳了再说话，小子。
你们那层有个叫鲍勃的，干了五年还在原地，这种人留着干什么？
今天把他 fire 掉。

[mail day4_mira from="米拉" faction=GROUND graded=no about=Mira if="not called(Mira)"]
subject: 电箱
上次说的停电，维修那边一直没来人。
你办公室的电箱再没人看，早晚出事。维修工的号码我再给一次：{caller:Repair}

[mail day4_bob from="鲍勃" faction=GROUND graded=no about=Bob if=did(promotion,Bob,ever)]
subject: 谢谢您
谢谢您。真的。五年了，第一次有人把我的档案读完。
这是我的号码：{caller:Bob}。有什么不方便走系统的事，可以打给我。
?if level.Bob>=3
我们这层的保洁大姐每天最后一个走，她的号码是 {caller:Cleaner}，您可能用得上。
?end

[score]
if did(promotion,me) -> B+2
if did(promotion,Bob) -> D+1
if did(fire,Bob) -> A+1
