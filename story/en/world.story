# Global setup: accounts, employee files, phone contacts, ending rules.
# Ids (the names in [profile X], roster:, order=, conditions) are NEVER translated —
# the save file keys logs and clearances by them. Only `name:` changes per language.

# ── Accounts ────────────────────────────────────────────

[account hrtemp]
pass: 4471
name: HR Lead
clearance: 2


# ── Employee files ──────────────────────────────────────

[profile Bob]
name: Bob
position: Clerk
department: Floor 3
faction: GROUND
clearance: 1
Five years in. No incidents on record, every review says "performs well".
Five years, not one promotion.

[profile Rick]
name: Rick
position: Clerk
department: Floor 3
faction: A
clearance: 1
One month in.
Two major incidents on file, neither acted on.
Review note: aggressive, rude to colleagues.

[profile Mira]
name: Mira
position: Supervisor
department: Floor 3
faction: GROUND
clearance: 3
Has been in this building longer than anyone else still on the payroll.
The last HR lead left a note about her. Nothing she knows was ever typed into the system.

[profile Banner]
name: Banner
position: Project Director
department: Executive
faction: A
clearance: 4
Says a thing once. Files he takes an interest in rarely need updating two weeks later.

[profile Roderick]
name: Roderick
position: General Manager
department: Executive
faction: B
clearance: 4
All smiles. Three of the people he vouched for are no longer on any floor's roster.


# ── Phone ───────────────────────────────────────────────

[contact Repair]
name: Maintenance

[call Repair]
them: "Maintenance. Which floor?"
me: Third. HR office. Something's wrong with the breaker box.
them: "Right. On my way up."
them: He drops his bag on your desk and crouches at the box. The key hangs off the strap, half a metre from your hand.
- "Take it while his back is turned." if="not flag:has_key" -> flag=has_key, C+1
- "Just watch him work." ->

[contact Mira]
name: Mira, floor 3

[call Mira]
them: (two seconds of silence) "...You're the new one. Nobody upstairs hears this line. You can talk straight."
them: "Anything on paper gets read. Your seat has had five people in three years. The last one left nothing on the desk."
them: "Banner and Roderick are after the same chair. You're just the hand they test each other with — every transfer you sign is somebody's ledger entry."
?if did(promotion,Rick,ever)
them: "Except you've already picked. You can see whose boy Rick is."
them: "...Forget I called."
?end
?if "not did(promotion,Rick,ever)"
them: "Chen in the security room has a recording. Banner threatening the last one — the hallway system caught all of it. He won't hand it in. Handing it in is the end of him."
them: "Here: {caller:Guard}. Don't use company mail for this."
me: Got it.
?end

[contact Bob]
name: Bob, floor 3

[call Bob]
them: "Hello? ...It really is you. Sorry, I'll keep my voice down."
them: "The file says five years without an incident. It also says five years without a promotion. You're the first person who read to the end."
me: What have you heard down there?
them: "Nothing from upstairs. But the cleaner on our floor leaves last every night, and she empties Roderick's bin."
?if "not level.Bob>=3"
them: "She doesn't know me, though. At my level I can't even badge onto that floor... I'm sorry."
?end
?if level.Bob>=3
them: "I can get onto that floor now. Her number is {caller:Cleaner}. Tell her I sent you."
?end
?if level.Bob>=4
them: "One more thing — my account got approval rights last night. A disciplinary needs two signatures. You sign one, I sign the other."
?end

[contact Guard]
name: Chen, security

[call Guard]
them: "...Who is this?"
me: Mira gave me this number.
them: (a long pause) "I kept the recording. Not to report anyone. Just in case."
them: "What Banner said to the last one — the machine got all of it."
- "Send it to me." -> flag=has_tape, D+1
- "I don't want any part of this." -> C+1

[contact Cleaner]
name: Mrs Zhou, cleaning

[call Cleaner]
them: "Bob said you'd call."
them: "I've emptied that office's bin for six years. Some things got torn up. Not all the way."
them: "I took photos. If you want them, they're yours."
- "Send them." -> flag=has_photo, D+1
- "No. Leave it." -> C+1


# ── Ending rules ────────────────────────────────────────
# Checked in order, first match wins; nothing matches -> fallback ending C.
# Three strikes is a separate path (game over -> ending E), it never reaches here.

[ending]
if "leading(A) and did(promotion,Rick,day5)" -> A
if "leading(B) and did(promotion,me,day5)" -> B
if leading(A) -> E
if leading(B) -> E
if "flag:has_tape and flag:has_photo and level.Bob>=4 and did(fire,Banner,day5) and did(fire,Roderick,day5)" -> D


# ── Ending cards ────────────────────────────────────────

[ending_text A]
title: RICK'S CHAIR
Rick outranks you now. He made room for his own people and cleared out a batch of old hands on the way — you among them.

[ending_text B]
title: SELF-APPROVED
The company found the promotion you signed for yourself. You were walked out the same day, and a lot of long-timers went with you that week.

[ending_text C]
title: NOTHING CHANGED
You, Mira and Bob were all cleared out. But neither of them won, and most of the floor is still there.

[ending_text D]
title: LEVEL FIVE
Once the material was filed, the system opened level five to you. The last two forms you signed were Banner's and Roderick's.

[ending_text E]
title: THREE STRIKES
Three mistakes. Security will see you out.


# ── Random employee names ───────────────────────────────

[names]
Jack, Tom, Kate, Sam, Leo, Mia, Dan, Zoe, Max, Amy
Ben, Eve, Cal, Ivy, Rex, Sue, Jay, Kim, Roy, Ann
Ted, Meg, Sid, Fay, Gus, Jan, Ned, Kay, Lou, Ray
