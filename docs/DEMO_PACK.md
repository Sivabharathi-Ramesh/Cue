# Cue — Demo pack for the NGO / Rotary meeting

**Presenter:** [your name]  
**Date:** [date]  
**Build:** Cue 1.0.1 demo, Android arm64 (`Cue-demo-1.0.1-arm64.apk`)  
**Language:** English only for this demo. Hindi stays in the build but is frozen and not shown.  
**Audience:** NGO leadership, Rotary club members, community-service chair, possibly a low-vision trainer

---

## The sentence to open with

> “Cue turns an ordinary Android phone into a reading and recognition assistant for blind and low-vision people — one live camera, one physical button, English today, and no internet needed for reading.”

Do not open with “we built an app.” Open with a person and a moment.

## The 60-second story

> “Imagine you cannot see the label on your child’s medicine. You have a smartphone, but every app assumes you can see a menu. So you wait for someone to help you.
>
> Cue removes that wait. You hold one button, point the phone, and it reads. It also knows when it cannot read something, and says so instead of guessing.
>
> We have built it, tested it, and made it work in Hindi and English without sending anything off the phone. What we need now is 20 people and 12 weeks to prove it works in daily life.”

Then stop talking and demo.

---

## 10-minute run sheet

| Time | What | Notes |
|---|---|---|
| 0:00–1:30 | The person and the problem | The medicine-label story. No jargon. |
| 1:30–2:30 | What Cue is | Three sentences, not a feature list. |
| 2:30–6:30 | Live demo | Airplane mode on. Eyes closed. Let it speak. |
| 6:30–8:00 | Evidence and honesty | Tests, languages, offline, failure case. |
| 8:00–9:00 | The pilot ask | 20 users, 12 weeks, one coordinator. |
| 9:00–10:00 | One question back to them | “Which of your programs would this fit?” |
| After | Listen | Do not fill silence with features. |

---

## Language policy for this demo

**English only.** Hindi remains in the build; it is not being removed. But for this phase it is frozen:

- No new Hindi strings, phrases, OCR work, or voice testing.
- No Hindi step in the demo.
- No claim that Hindi is validated or ready for users.

If someone asks to see Hindi, say:

> “We are keeping this demo English-only. Hindi is in the build, but we will validate it separately with Hindi speakers before we claim it. We would rather do one language properly than two languages badly.”

That answer is stronger than a rushed Hindi demo.

---

## Demo sequence — rehearse exactly this

1. **Set the stage.** “Everything you are about to see works with no internet.” Turn on airplane mode and show the screen to the room.
2. **Close your eyes.** Hold volume-down for half a second, say “read,” let go. Hold a medicine strip or a printed bill in front of the camera.
3. **Let it read two or three sentences.** Then say “stop” (or swipe up). Do not let it read a whole page in silence.
4. **Object mode.** Swipe sideways to Object. Hold a clear object — a blue mug or a bottle — about 30–50 cm away. Say “what is this?” or double-tap. Let it say the name, colour, direction, and a rough distance when it can estimate one.
5. **A side question.** “What is on my left?” Show that it can answer a direct spatial question.
6. **The failure case.** Point at a handwritten note (the refusal is expected) or a blank wall. Let Cue say it cannot read the marks. Then say: “That is the safety feature. A blind user cannot check a wrong medicine label. Cue refuses rather than guesses. Printed text is the pilot scope; handwriting is Phase 2.”
7. **The dark screen.** Let the preview fade to black. Explain: “The screen is for sighted helpers. It goes dark for privacy and battery. The phone keeps working.”
8. **The ask.** “We are not asking for a national rollout. We are asking for a 12-week pilot with 20 of your members.”

If a step fails, do not apologise repeatedly. Say what happened, use the fallback, and move on.

---

## Fallbacks if the demo misbehaves

| Problem | What to do | What to say |
|---|---|---|
| Voice command does not work offline | Use double-tap to read; use the on-screen gesture for mode change | “Reading and object detection are offline. Voice uses the phone’s speech engine; the offline pack is not installed on this phone.” |
| Someone asks to see Hindi | Stay in English; do not switch | “We are keeping this demo English-only. Hindi is in the build, and we will validate it separately with Hindi speakers before we claim it.” |
| Object detection misses | Move closer, improve light, use a plainer object, wait 2 seconds | “It needs a clear view and a moment to confirm; it will not guess from one frame.” |
| Camera fails | Close other camera apps, restart the phone, use the backup phone | “Android gives the camera to one app at a time.” |
| Location fails indoors | Skip it; use time, date, battery | “Location needs a fix; indoors it honestly says it cannot get one.” |
| App crashes | Restart; if it repeats, play the 2-minute video | “This is why we are asking for a pilot, not a rollout.” |
| Screen goes black | Double-tap to bring the preview back | “That is intentional: privacy and battery.” |

---

## Q&A cheat sheet

**“Why not Google Lookout, Seeing AI, or Be My Eyes?”**  
“Those are excellent, and we recommend them. They are built for someone comfortable with a touchscreen, a mode menu, and often an internet connection. Cue is built for a person who cannot see the screen at all: one live camera, one physical key, English today, no menu, no internet for reading. We are not trying to beat Google. We are trying to reach the person their design assumes away.”

**“How accurate is it?”**  
“For printed text in good light, it is useful today. For handwriting or poor light, it refuses instead of guessing. The pilot measures task success; we are not claiming perfection.”

**“Can it read handwriting?”**  
“Not today. It reads printed text. Point it at handwriting and it will refuse rather than guess. We would rather say ‘I can’t read this’ than read the wrong dosage. Handwriting is a Phase 2 question, and it may need a different model or an online mode.”

**“Can it replace a cane or a guide dog?”**  
“No. It is not a mobility aid. It reads and identifies. A cane, a guide dog, and mobility training remain essential.”

**“Who pays?”**  
“Free for users. The pilot is funded by Rotary/CSR. After the pilot, we will fund support and training through institutional partnerships and grants. No ads, no data selling.”

**“What data do you collect?”**  
“Nothing leaves the phone by default. No accounts, no images stored, no audio stored. For the pilot we will ask consent for simple usage counts — reads, objects, errors — with no personal data, and users can say no.”

**“What do you need from us?”**  
“Twenty users through your low-vision or blind-school network, one coordinator, a training venue, and ₹1.5–3 lakh or in-kind support for training, transport, and evaluation. If it works, we will have the evidence for a larger project.”

**“What is the timeline?”**  
“Two weeks to set up, twelve weeks of use, two weeks of analysis. A written report and three case studies at the end.”

**“What if it fails?”**  
“Then we will have learned which tasks it cannot do and why. A pilot that finds a failure is cheaper than a rollout that hides one.”

**“Why should Rotary fund software?”**  
“Because the cost per beneficiary falls as it scales. The first 20 users cost money for training and evaluation; the next 2,000 cost almost nothing. And it complements your eye-health work: 80% of blindness is avoidable, but millions live with it today.”

**“Can you customise it for our NGO?”**  
“Yes, within the pilot: branding, training, and reports. We will not promise custom features that break the core experience.”

**“Who owns the IP?”**  
“We own the app. The NGO gets a free license for the pilot, and users get free use. We do not want exclusivity; we want evidence.”

---

## What to look for in the room

### Decision-makers
- Club president and community-service chair.
- The NGO director or programme manager.
- The low-vision trainer or rehabilitation officer.
- A blind or low-vision member who can speak for the users.
- The person who controls the budget and the person who controls the calendar.

### Good signals
- They ask how many users can start, who trains them, and what it costs per person.
- They mention a specific school, clinic, association, or camp.
- They ask to try the phone themselves.
- They introduce you to someone else in the room.
- They ask about timelines, reporting, and safeguarding.
- They say “we could start with a small group.”

### Questions to ask them
1. “Which of your current programmes touches blind or low-vision adults?”
2. “How many members could try this in the next four weeks?”
3. “Who would train and support them?”
4. “What outcomes do you report to your board or funders?”
5. “What would make this a yes for you?”
6. “What would make it a no?”
7. “Who else should be in this conversation?”
8. “Can we agree a date to see the pilot site?”

### Red flags in the room
- Praise with no questions.
- “Send us a proposal” with no date or named person.
- A request for exclusivity or ownership at the first meeting.
- A demand for features you cannot deliver.
- No blind or low-vision person involved.
- Treating it as a one-time charity demo, not a pilot.

### Red flags in your own pitch
- A feature tour instead of a person’s story.
- Claiming it replaces a cane.
- Hiding the AGPL detector or the debug-signed build.
- Asking for a large grant before a pilot.
- Demoing Currency or Screen mode, which are not built.
- Talking for ten minutes without letting them touch the phone.

---

## The ask — say it exactly

> “We are not asking for a grant today. We are asking you to host a 12-week pilot with 20 users through your low-vision or blind-school network, with one coordinator and ₹1.5–3 lakh or in-kind support for training, transport, and evaluation. If it works, we will have the evidence for a larger Rotary or CSR project. Can we agree a date in the next two weeks to meet the pilot site?”

Do not leave without a named contact and a next date.

---

## Night-before checklist

- [ ] Freeze the code. No new features tonight.
- [ ] Uninstall any old Cue build from both demo phones.
- [ ] Install `Cue-demo-1.0.1-arm64.apk` on both phones.
- [ ] Open once, grant camera/mic/location, close, reopen.
- [ ] Put both phones in airplane mode. Test reading and object mode.
- [ ] Download the English offline speech pack; test the volume-down command in airplane mode.
- [ ] Uninstall any old build first, so a saved Hindi setting cannot come back. Confirm the phone opens in English.
- [ ] Test the volume-down long press, double-tap, two-finger tap, swipes, and the dark screen.
- [ ] Run a 20-minute session; note battery drop and whether the phone gets hot.
- [ ] Record a 2-minute backup video: reading, object, side question, Hindi, failure case.
- [ ] Print the one-pager (large font), privacy note, and pilot proposal.
- [ ] Pack: two phones, charger, power bank, phone stand, medicine strip, bill/letter, Hindi book, mug/bottle, handwritten note.
- [ ] Rehearse three times, out loud, with a timer.
- [ ] Charge both phones and the power bank overnight.

## Demo-day checklist

- [ ] Arrive 30 minutes early.
- [ ] Turn on Do Not Disturb; close other apps; clear recent apps.
- [ ] Test camera, mic, TTS, voice, and airplane mode in the actual room.
- [ ] Check the phone volume and the room acoustics.
- [ ] Have the backup phone and the video ready.
- [ ] Put the one-pager, privacy note, and proposal on the table.
- [ ] Keep the demo to 10 minutes. Leave the rest for questions.
- [ ] Ask for a next date before you leave.
- [ ] Send a thank-you and the proposal within 24 hours.

---

## Do not do

- Do not add features tonight.
- Do not demo Currency or Screen mode.
- Do not switch to Hindi during this demo.
- Do not claim it replaces a cane or provides navigation.
- Do not hide the AGPL detector or the debug signing.
- Do not ask for a global grant at the first meeting.
- Do not present alone if the NGO or a blind user can join you.
- Do not overclaim accuracy; show a failure.
- Do not leave without a next step.
