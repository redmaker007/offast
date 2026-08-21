# 第 2 天：A 派头目班纳登场，一封 4 级命令把当天所有随机员工全部辞退。
# 米拉暗示去开电箱——那里有她的号码。

[day]
filler: 5
roster: Bob

[story]
them: 第二天。
them: 昨天会计部有人被清掉了。没人说为什么。

[mail day2_banner from="班纳" faction=A class=4 order=fire:*random about=Banner]
subject: 照我说的做
嘿新来的小子，欢迎你的到来。
帮我做件事：我相信你看到之前那些邮件了吧。别管之前的指示，
把前面信件提到的员工全部 fire 掉。这是命令。

[mail day2_mira from="米拉" faction=GROUND graded=no about=Mira]
subject: 停电
你好，项目部主管。最近公司好像频繁停电。
没事的时候最好让维修工检查一下你办公室的电箱。
对了，维修工的号码是 {caller:Repair}。

[electricbox repeat=yes]
?if "not flag:has_key"
them: 电箱锁着。锁孔上有新的划痕，像是有人常开。
me: 钥匙在维修部手里。
?end
?if flag:has_key
them: 钥匙转了半圈，箱门开了。里面贴着一张手写的纸条。
them: "有事打这个：{caller:Mira}"
- "记下来。" -> flag=got_mira_number, C+1
?end

[score]
if did(fire,*random) -> A+2
if "not did(fire,*any)" -> C+2
