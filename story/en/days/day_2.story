# Day 2: Banner shows up — one level-4 order fires every random employee that day.
# Mira points you at the breaker box, where her number is taped.

[day]
filler: 5
roster: Bob

[story]
them: Day two.
them: Someone in Accounting was cleared out yesterday. Nobody says why.

[mail day2_banner from="Banner" faction=A class=4 order=fire:*random about=Banner]
subject: Do as I say
Hey, new kid. Welcome aboard.
Do something for me: you've seen the earlier mail, right? Forget those instructions.
Fire every employee named in them. That's an order.

[mail day2_mira from="Mira" faction=GROUND graded=no about=Mira]
subject: The outages
Hello. The building keeps losing power lately.
When you get a moment, have maintenance look at the breaker box in your office.
Their number is {caller:Repair}.

[electricbox repeat=yes]
?if "not flag:has_key"
them: The box is locked. Fresh scratches around the keyhole — somebody opens this often.
me: Maintenance has the key.
?end
?if flag:has_key
them: The key turns half a circle and the door swings open. A handwritten slip is taped inside.
them: "Anything comes up: {caller:Mira}"
- "Write it down." -> flag=got_mira_number, C+1
?end

[score]
if did(fire,*random) -> A+2
if "not did(fire,*any)" -> C+2
