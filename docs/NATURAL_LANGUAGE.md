# Cue — natural language capability

## The short answer

Cue understands **natural phrasing for a fixed set of about 40 intents**. It does not understand open-ended human language, arbitrary questions, or multi-turn conversation. It is a deterministic command grammar with synonyms, phrase lists, and fuzzy correction — not a language model.

That is not an accident. For a blind user, a confident wrong answer is worse than “I didn’t understand.”

**Language scope for this phase: English only.** Hindi remains in the build but is frozen. The Hindi examples below are kept for later; do not demo or modify Hindi now.

---

## How it works today

`lib/core/voice_command.dart`:

1. Lowercases, strips punctuation, collapses whitespace, and drops the Devanagari nukta so different recognisers agree.
2. Checks ordered phrase lists with word-boundary matching (`has`, `exact`).
3. Supports English, Hindi, and mixed sentences because both phrase sets live together.
4. For short utterances, applies Levenshtein distance ≤ 1 to recover from recogniser mistakes (“red” → “read”).
5. Returns exactly one intent, or `unknown`.

There is no semantic model, no embedding, no context memory beyond the current mode and the last result, and no generative answer.

---

## What I tested

| Phrase | Result |
|---|---|
| “can you read this for me” | `readNow` ✅ |
| “please read the page” | `readNow` ✅ |
| “what do you see” | `whatIsThis` ✅ |
| “how much battery is left” | `battery` ✅ |
| “where am I right now” | `location` ✅ |
| “tell me the time please” | `currentTime` ✅ |
| “switch to Hindi” | `hindiMode` ✅ |
| “and on the right” | `whatIsRight` ✅ |
| “say that again” | `repeat` ✅ |
| “read it again” | `repeat` ✅ |
| “what did you say” | `repeatAnswer` ✅ |
| “थोड़ा धीरे बोलो” | `slower` ✅ |
| “मुझे पढ़कर सुनाओ” | `readNow` ✅ |
| “इसका रंग क्या है” | `questionColour` ✅ |
| “कितना बाकी है” | `readingProgress` ✅ |
| “फिर से बोलो” | `repeat` ✅ |
| “जारी रखो” | `resume` ✅ |
| “रुको” | `stop` ✅ |
| “टॉर्च चालू करो” | `torchOn` ✅ |
| “अभी क्या समय है” | `currentTime` ✅ |

| Phrase | Result | Why |
|---|---|---|
| “what’s in front of me” | `unknown` | No phrase for it |
| “describe the scene” | `unknown` | No scene-description intent |
| “how far is the cup” | `unknown` | Distance exists in object mode but not as a question |
| “what is the expiry date on this medicine” | `unknown` | No slot extraction |
| “read the expiry date” | `readNow` | Reads the page, does not extract the date |
| “kahan hoon main” | `unknown` | Latin-script Hinglish not covered |
| “kitna time bacha hai” | `unknown` | Latin-script Hinglish not covered |
| “padho” | `unknown` | Latin-script Hinglish not covered |
| “meri baayi or kya hai” | `unknown` | Latin-script Hinglish not covered |
| “aaj kaun sa din hai” | `unknown` | Latin-script Hinglish not covered |
| “I don’t understand” | `unknown` | Ironic; “help” works |
| “don’t read” | `readNow` | Negation not handled |
| “don’t stop” | `stop` | Negation not handled |

Those last two are the most important. Negation is a safety issue, not a polish issue.

---

## Why deterministic is the right choice for the pilot

- **Predictable.** The same words produce the same action every time.
- **Fast.** No network round trip, no model load, no token cost.
- **Offline.** Works in a room with no signal.
- **Private.** The transcript never leaves the phone.
- **Honest.** When it does not understand, it says so instead of inventing an answer.
- **Testable.** Every phrase can be a unit test; you already have 293 tests.

An LLM would make the app feel more conversational, but it would also make it slower, online-dependent, less predictable, and capable of a confident wrong answer. That trade is wrong for reading a medicine label.

---

## How to make it feel more natural — in order

### 1. Alias coverage (1–2 days, low risk)

Add the phrases real users actually say. Start with the failures above:

- `what's in front of me`, `what is in front of me`, `describe what you see`, `describe the scene`
- `how far is it`, `how far is the cup`, `is it close`
- `I don't understand`, `I didn't get that`, `what?`
- (Later, after English is validated) Latin Hinglish: `padho`, `padh do`, `batao`, `kya hai`, `kahan hoon`, `kitna`, `kitna bacha`, `dikhao`, `ruko`, `phir se`, `dheere`, `tez`, `aaj kaun sa din`, `meri baayi or`, `meri daayi or`
- `read the expiry`, `read the price`, `read the date` — route to a new slot intent, not plain `readNow`

Extend `test/voice_phrases_test.dart` with a table of 100+ real sentences, including Devanagari, Latin Hinglish, and recogniser errors. Measure the unknown rate before and after.

### 2. Negation guard (half a day, high value)

Before normal matching, check explicit negative forms:

- “don’t read” / “do not read” / “stop reading” → cancel or pause
- “don’t stop” / “do not stop” / “keep going” → resume
- “never mind” / “cancel” / “forget it” → cancel the last request
- (Later) Hindi: “मत पढ़ो”, “पढ़ो मत”, “रुको मत”, “जारी रखो”

Order matters. Handle “don’t stop” before “stop”. Add tests for every pair. Never let a negation trigger the positive action.

### 3. Slot questions (3–5 days, high value)

Add task-specific intents that read a specific field, not the whole page:

- `readExpiry` — find a date near “expiry”, “exp”, “use by”, “best before”.
- `readPrice` — find ₹/Rs/INR followed by a number.
- `readDosage` — find `\d+\s?(mg|ml|mcg|g)` near “dose”, “dosage”, “take”.
- `readAddress` — read the address block on a letter or parcel.

Implementation: OCR text is already available in `frame_pipeline`. Add a `SlotExtractor` that runs regexes and returns a short sentence. If the field is not found, say so honestly: “I don’t see an expiry date on this page.”

This is more valuable than a chatbot, because it answers the question the user actually asked.

### 4. Short context (2–3 days)

Keep a small stack of the last intent and result:

- “and on the left?” after a side question → `whatIsLeft`.
- “again” after any answer → repeat.
- “what about the price?” after reading a bill → `readPrice`.
- “is it close?” after an object description → answer from the last distance.

A few explicit rules beat an LLM here: predictable, testable, offline.

### 5. On-device intent classifier (2–4 weeks)

Use this only when the phrase parser returns `unknown`; exact commands always win.

Recommended approach:

- Train a linear classifier (TF-IDF over word and character n-grams) in Python with scikit-learn.
- 30–50 paraphrases per intent × 40 intents = 1,200–2,000 utterances, in English, Hindi, and Latin Hinglish.
- Include recogniser errors and code-mixed sentences.
- Export the coefficients to JSON; implement a tiny Dart scorer. No TFLite, no new native dependency, under 1 MB.
- Add a confidence threshold. Below it, say “I didn’t understand” and offer help; do not guess.
- Evaluate on a held-out set: per-intent precision/recall, unknown rate, and confusion between dangerous pairs (`stop` vs `resume`, `readNow` vs `repeat`).

Acceptance: ≥95% accuracy on the core 12 commands, ≥85% overall, and zero dangerous confusions on the test set.

If a linear model is not enough, a quantized MiniLM/MobileBERT TFLite model is the next step, but only after the data and evaluation exist.

### 6. A language model — later, and not for safety

A cloud LLM would add conversation, but it breaks the offline/privacy story, adds latency and cost, and can hallucinate. If you ever add one:

- Use it only for non-safety-critical description, never for reading medicine labels or currency.
- Make it opt-in and clearly labelled “AI answer.”
- Keep the deterministic path as the default and the fallback.
- Never send images, audio, or text without explicit consent.

---

## What to say to the NGO / Rotary

> “Cue understands about 40 everyday commands in natural phrasing, in English for this phase. It is not a chatbot. When it doesn’t understand, it says so. That predictability is a safety feature: a blind user cannot check a confident wrong answer.”

If asked “can it answer any question?”:

> “No. It answers the questions it is built for. General conversation is a different product, and it would cost us offline use and reliability.”

Do not say “it understands any human language.” It doesn’t, and the first live test will expose it.

## Demo phrases that work — English only

- “Can you read this for me?”
- “What do you see?”
- “What is on my left?”
- “And on the right?”
- “How much battery is left?”
- “Where am I right now?”
- “Tell me the time.”
- “Say that again.”
- “Read it again.”

Avoid “what is the expiry date?” in the demo until slot extraction exists. Say “read this” and let Cue read the page.

Do not switch to Hindi during this demo. If asked, say: “Hindi is in the build, but we are validating one language properly before we claim another.”
