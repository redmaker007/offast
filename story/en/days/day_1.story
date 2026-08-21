# Day 1: onboarding. Learn to read mail and fill the personnel form.
# The laptop login is printed on page 1 of the pad on the desk.
# Bob shows up for the first time — his request is never graded, it only moves scores.

[day]
filler: 4
roster: Bob

[story]
them: Day one.
them: You got the job. Read the mail, do what it says.
them: The system deletes mail once you've read it. Company policy.
them!: The laptop wants a login. Whoever sat here before you left a pad on the desk.

[mail day1_roderick from="Roderick" faction=B graded=no about=Roderick]
subject: Good to meet you!
Our new HR lead! I'm the general manager here at Offast.
Anything you need, don't be shy about asking me!

[mail day1_mira from="Mira" faction=GROUND graded=no about=Mira]
subject: Congratulations
Hello, new HR lead. Congratulations on the appointment.
Good luck.

[mail day1_bob from="Bob" faction=GROUND graded=no about=Bob]
subject: Raise request
Hello, I would like to request a raise.
I've been with the company five years and have never made an error.
Thank you for your time.

[caller]
them: The phone rings twice and stops. Then once more.
them: "Reception. Just testing the line at the new desk. You hear me?"
me: I hear you.
them: "Good. You'll be hearing from us." Click.

[score]
if did(raise,Bob) and did(promotion,Bob) -> D+1
if "did(raise,Bob) and not did(promotion,Bob)" -> C+1
