# 全局设定：系统账户 + 员工档案 + 电话联系人。整局都在，不属于任何一天。
#
# 账户的 clearance 决定查得到哪些档案（账号等级 >= 档案等级就整份可见）。
# 主角自己是 2 级：查得到鲍勃和瑞克，查不到米拉（3 级）和两个头目（4 级）。
#
# 电话号码留空 = 每局随机 4 位（防背点）。文案里写 {caller:名字}，显示时才换成真号码。
# 号码要抄进桌上那本记事本——一行只有 6 个字符。


# ── 账户 ────────────────────────────────────────────────

# 主角自己的号。密码印在记事本第 1 页。
[account hrtemp]
pass: 4471
name: 人事部主管
clearance: 2


# ── 员工档案 ────────────────────────────────────────────

[profile Bob]
name: 鲍勃
position: 职员
department: 三楼
faction: GROUND
clearance: 1
入职五年。没有任何失误记录，考评一直是「表现良好」。
五年里没有得到过一次 promotion。

[profile Rick]
name: 瑞克
position: 职员
department: 三楼
faction: A
clearance: 1
入职一个月。
两次重大失误在案，均未处理。
考评备注：攻击性强，对同事无礼。

[profile Mira]
name: 米拉
position: 主任
department: 三楼
faction: GROUND
clearance: 3
在这栋楼里待的时间比任何还在职的人都长。
上一任人事主管留下过一张关于她的便条。她知道的事，一件也没写进系统。

[profile Banner]
name: 班纳
position: 项目部总监
department: 高层
faction: A
clearance: 4
说一不二。被他点过名的人，档案通常两周之内就不需要更新了。

[profile Roderick]
name: 罗德里克
position: 项目部总经理
department: 高层
faction: B
clearance: 4
笑面虎。他担保过的人里，有三个已经不在任何一层的名册上了。


# ── 电话 ────────────────────────────────────────────────

[contact Repair]
name: 维修部

[call Repair]
them: "维修部。哪一层？"
me: 三楼，人事这间。电箱好像有问题。
them: "行，我这就上来。"
them: 他把工具袋往桌上一放，蹲下去看电箱。钥匙就挂在袋子外侧，离你半米。
- "趁他背对着，把钥匙拿走。" if="not flag:has_key" -> flag=has_key, C+1
- "站在旁边看他弄完。" ->

[contact Mira]
name: 米拉 · 三楼

[call Mira]
them: （沉默了两秒）"……你是新来的那个。这条线上级听不到，说话可以直接一点。"
them: "写在纸上的东西会被人看见。你这个位置，三年换了五个人。上一个走的那天，桌上什么都没留下。"
them: "班纳和罗德里克在争同一个位置。你只是他们互相试探的那只手——你签的每一张调动单，都是他们记账用的。"
?if did(promotion,Rick,ever)
them: "不过你已经选了。瑞克是谁的人，你不会看不出来。"
them: "……算了，就当我没打过这通电话。"
?end
?if "not did(promotion,Rick,ever)"
them: "保安室的老陈手里有一段录音。班纳威胁上一任的时候，走廊的机器录下来了。他不敢交上去，交上去就是他没了。"
them: "号码给你：{caller:Guard}。别用公司邮件联系他。"
me: 记下了。
?end

[contact Bob]
name: 鲍勃 · 三楼

[call Bob]
them: "喂？……真的是您。抱歉，我这边小声一点。"
them: "档案上写着我五年没有失误，也写着我五年没升过一次。您是第一个把它读完的人。"
me: 你在这儿听到过什么？
them: "楼上的事我不清楚。但我们这层的保洁大姐每天最后一个走，罗德里克办公室的纸篓是她倒的。"
?if "not level.Bob>=3"
them: "可她不认识我。我这个级别，连那层楼的门禁都刷不开……对不起。"
?end
?if level.Bob>=3
them: "现在我进得去那层了。她的号码是 {caller:Cleaner}，您就说是我介绍的。"
?end
?if level.Bob>=4
them: "对了——系统昨晚给我开了审批权限。人事处分要两个人签字，您签一个，我签一个。"
?end

[contact Guard]
name: 老陈 · 保安室

[call Guard]
them: "……谁？"
me: 米拉给我的号码。
them: （很长的沉默）"那段录音我留着。不是为了告谁，是为了万一。"
them: "班纳跟上一个人说的那句话，机器完整录下来了。"
- "把录音发给我。" -> flag=has_tape, D+1
- "我不想搅进去。" -> C+1

[contact Cleaner]
name: 周姐 · 保洁

[call Cleaner]
them: "鲍勃说过你会打来。"
them: "那间办公室的纸篓我倒了六年。有些东西撕了，但没撕干净。"
them: "我拍了照片。你要，我就发给你。"
- "发给我。" -> flag=has_photo, D+1
- "不用了。" -> C+1


# ── 结局判定 ────────────────────────────────────────────
# 按顺序判，第一条成立的算数；都不成立走兜底结局 C。
# 三次失误（三条命掉光）是另一条路，不经过这里，直接结局 E。

[ending]
if "leading(A) and did(promotion,Rick,day5)" -> A
if "leading(B) and did(promotion,me,day5)" -> B
if leading(A) -> E
if leading(B) -> E
if "flag:has_tape and flag:has_photo and level.Bob>=4 and did(fire,Banner,day5) and did(fire,Roderick,day5)" -> D


# ── 结局文案 ────────────────────────────────────────────

[ending_text A]
title: 瑞克上位
瑞克的权限比你高了。他让出位置给自己人，顺手清掉了一批老员工——包括你。

[ending_text B]
title: 违规提拔
公司查到你给自己批了 promotion。你被当场辞退，同一周还有一大批老员工陪着你走。

[ending_text C]
title: 维持原样
你、米拉、鲍勃一起被清掉了。但两个头目谁也没赢，大批员工留了下来。

[ending_text D]
title: 五级权限
证据递上去之后，系统给了你 5 级权限。你签的最后两张表，是班纳和罗德里克的。

[ending_text E]
title: 失误太多
三次失误。保安会送你出去。


# ── 随机员工的名字池 ────────────────────────────────────
# 剧情角色不在这里，这些只是每天陪跑的路人。

[names]
王磊, 李娜, 张伟, 刘洋, 陈静, 杨帆, 赵敏, 周涛, 吴迪, 郑爽
孙浩, 马丽, 朱强, 胡萍, 林峰, 何勇, 高翔, 罗兰, 梁爽, 宋佳
唐宁, 韩雪, 冯刚, 邓超, 曹颖, 彭辉, 曾莉, 萧然, 田甜, 董明
