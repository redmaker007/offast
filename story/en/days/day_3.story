# Day 3: both sides push. Rick enters the form via Banner's level-4 order,
# and Bob asks for a promotion the same day — one slot, so it's a choice.

[day]
filler: 3
filler_exclude: promotion
roster: Bob

[story]
them: Day three.
them: Two directors are sending orders that contradict each other. Rank wins.

[mail day3_roderick from="Roderick" faction=B graded=no about=Roderick]
subject: Are you holding up?
I noticed Banner has been sending you some unreasonable instructions.
If there's an instruction you'd rather not carry out, then don't.
Remember, I'm always on your side.

[mail day3_rick from="Rick" faction=A graded=no about=Rick]
subject: promotion
Old man. Give me my promotion.

[mail day3_banner_a from="Banner" faction=A class=4 order=promotion:Rick about=Banner if=score.A>=2]
subject: Not bad
Hey kid! Good work yesterday!
There's an excellent employee named Rick with a promotion pending. Push it through for me.

[mail day3_banner_b from="Banner" faction=A class=4 order=promotion:Rick about=Banner if="not score.A>=2"]
subject: Open your eyes
Did you misread my instruction yesterday? Open your eyes, kid.
Approve Rick's promotion today. Don't get it wrong again.

[mail day3_bob from="Bob" faction=GROUND graded=no about=Bob]
subject: Promotion request
Hello! I would like to request a promotion.
?if did(promotion,Bob,ever)
About last time... thank you, really. I won't make trouble for you.
?end
?if "did(raise,Bob,ever) and not did(promotion,Bob,ever)"
The adjustment came through. Thank you for remembering me.
?end

[score]
if did(promotion,Bob) -> D+1
if did(promotion,Rick) -> A+1
if did(reduction,Rick) -> B+1
if did(fire,Rick) -> B+2
