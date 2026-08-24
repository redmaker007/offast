# Day 4: both bosses react to what you did to Rick on day 3.
# Banner's angry version carries a level-4 order to fire Bob — the only way Bob
# gets onto the form today. Your own row only shows up when Roderick actually hints
# at it ("think about yourself for once") — nobody brings it up, it is not an option.

[day]
filler: 2
roster: Bob
roster: me if=did(fire,Rick,day3)

[story]
them: Day four.
them: Nobody says good morning in the corridor.

[mail day4_roderick_a from="Roderick" faction=B graded=no about=Roderick if=did(promotion,Rick,day3)]
subject: I did warn you
I did warn you. You can see by now whose boy that kid is.
There's still time.

[mail day4_roderick_b from="Roderick" faction=B graded=no about=Roderick if=did(reduction,Rick,day3)]
subject: Nicely done
Nicely done. Somebody has to teach the young ones the rules.

[mail day4_roderick_c from="Roderick" faction=B graded=no about=Roderick if=did(fire,Rick,day3)]
subject: Good work
Good work — that sort should have been out long ago.
And listen: you've done a lot for this company, you should think of yourself too.
Your clearance is enough to approve your own promotion. Nobody would say a word.

[mail day4_banner_a from="Banner" faction=A graded=no about=Banner if=did(promotion,Rick,day3)]
subject: Sharp
Not bad, kid. Sharp. One more thing on Friday — don't drop it.

[mail day4_banner_b from="Banner" faction=A class=4 order=fire:Bob about=Banner if="not did(promotion,Rick,day3)"]
subject: In one ear?
My instruction went in one ear and out the other?
Make sure your seat is steady before you talk back, kid.
There's a Bob on your floor. Five years, still in the same chair. What's he for?
Fire him today.

[mail day4_mira from="Mira" faction=GROUND graded=no about=Mira if="not called(Mira)"]
subject: The box
Maintenance still hasn't come about the outages.
If nobody looks at that breaker box, something will happen. Their number again: {caller:Repair}

[mail day4_bob from="Bob" faction=GROUND graded=no about=Bob if=did(promotion,Bob,ever)]
subject: Thank you
Thank you. Really. Five years, and you're the first to read my file to the end.
This is my number: {caller:Bob}. If something can't go through the system, call me.
?if level.Bob>=3
The cleaner on our floor leaves last every night. Her number is {caller:Cleaner} — you may need it.
?end

[score]
if did(promotion,me) -> B+2
if did(promotion,Bob) -> D+1
if did(fire,Bob) -> A+1
