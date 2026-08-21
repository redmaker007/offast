# Day 5: which mail arrives depends on which score leads; **today's actions decide the ending**.
# Priority table lives in world.story's [ending] block.

[day]
filler: 0
roster: Bob, Rick, me

[story]
them: Day five.
them: Last day of the week. Just get through it.

# Case 1: A and B tied and both ahead — one mail each, pick a side.
[mail day5_banner_tie from="Banner" faction=A class=4 order=promotion:Rick about=Banner if="tied(A,B) and leading(B)"]
subject: One last thing
One last thing. Rick's promotion. Today.

[mail day5_roderick_tie from="Roderick" faction=B graded=no about=Roderick if="tied(A,B) and leading(B)"]
subject: Ignore him
Ignore him. Approve your own promotion today — I'll vouch for it.

# Case 2: A leads.
[mail day5_banner from="Banner" faction=A class=4 order=promotion:Rick about=Banner if="leading(A) and not tied(A,B)"]
subject: Push it through
Push Rick's promotion through today. There's something in it for you after.

# Case 3: B leads.
[mail day5_roderick from="Roderick" faction=B graded=no about=Roderick if="leading(B) and not tied(A,B)"]
subject: You've earned it
You've had a long week. Approve yourself a promotion. I'll vouch for it, nobody checks.

# Case 4: C or D leads.
[mail day5_mira from="Mira" faction=GROUND graded=no about=Mira if="leading(C) or leading(D)"]
subject: After today
After today there's no chance. You know what you're holding.

[mail day5_bob from="Bob" faction=GROUND graded=no about=Bob if=level.Bob>=4]
subject: I'll sign
My clearance went up last night. I can co-sign a disciplinary now.
Whoever you're moving, I'll sign.

# With the evidence filed, the two bosses appear on your form (temporary level five).
[mail day5_board from="Compliance" graded=no order=fire:Banner about=Banner if="flag:has_tape and flag:has_photo and level.Bob>=4"]
subject: Material received
Your submission has been accepted. The disciplinary forms are open on your account.
Please complete them today.

[mail day5_board2 from="Compliance" graded=no order=fire:Roderick about=Roderick if="flag:has_tape and flag:has_photo and level.Bob>=4"]
subject: Material received (2)
Second form, same as above.
