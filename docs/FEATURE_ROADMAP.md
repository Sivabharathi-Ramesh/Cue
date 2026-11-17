# Cue — feature roadmap and implementation notes

This is ordered by what matters for the NGO pilot, not by what is fun to build.

**Rule:** do not add features the night before a demo. Freeze the build, rehearse, and ship the pilot with what works.

**Language:** English only for this phase. Hindi stays in the build but is frozen — no new Hindi strings, phrases, OCR work, or voice testing until English is validated with real users.

---

## Priority 0 — before the demo (zero-risk packaging only)

| Change | Why | Where | Effort |
|---|---|---|---|
| Replace the stock Flutter icon and launch screen | The first ten seconds signal “student project” | `android/app/src/main/res/mipmap-*/`, `ios/Runner/Assets.xcassets/AppIcon.appiconset/` | 1–2 h |
| Add an About entry | Version, contact, privacy note for NGO staff | New `lib/widgets/about_sheet.dart`; small info button in the status panel | 1 h |
| Show the current mode in the status panel | A sighted trainer needs to see Text/Object | `_statusPanel()` in `lib/live/live_screen.dart` | 30 min |
| Skip unbuilt modes in the swipe cycle | Avoid a demo dead end at “Banknote is not built” | `Interpretation.next/previous` in `lib/live/scene_router.dart`; tests | 1 h |
| Fix the unused `dart:math` import | Clean analyzer output | `lib/vision/detected_object.dart` | 1 min |
| Write a real README and pin Flutter 3.47.9 | Reproducible demo and handover | `README.md` | 30 min |

Do these only if you can rebuild, run `flutter test`, and reinstall by early evening. Otherwise, freeze the current build.

---

## Priority 1 — pilot blockers (2–4 weeks)

### 1. Signed release build and distribution

**Why:** the current release is signed with the debug key. Pilot users cannot receive clean updates.

**How:**
1. Generate a keystore: `keytool -genkey -v -keystore cue-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias cue`.
2. Create `android/key.properties` (never commit it):
   ```
   storePassword=...
   keyPassword=...
   keyAlias=cue
   storeFile=../cue-release.jks
   ```
3. Read `key.properties` in `android/app/build.gradle.kts` and create a `release` signing config; replace the debug signing config.
4. Add `key.properties` and `*.jks` to `.gitignore`.
5. Build an AAB: `flutter build appbundle --release`.
6. Use Google Play internal testing for the pilot, or a signed APK with a documented update process.
7. Publish the privacy policy and complete the Play data-safety form.

**Acceptance:** a pilot user can install from a link and receive an update without uninstalling.

### 2. First-run onboarding and language choice

**Why:** a new blind user currently hears an English intro and must remember four gestures. The first five minutes decide whether they keep the app.

**How:**
- Replace `lib/core/voice_intro.dart` with an `onboarding.dart` service that stores a step number and language choice in a small JSON file in the app support directory.
- On first launch, speak a bilingual welcome: “Cue. For Hindi, say Hindi. For English, double tap.”
- Then run three short practice tasks: (1) double-tap to read a label, (2) hold volume-down and say “what is this?”, (3) say “help”.
- Confirm each success with a distinct earcon and a short sentence.
- Add a voice command “tutorial” and a long-press path to replay it.
- Store completion so it does not repeat; allow “skip”.

**Acceptance:** five new blind users can complete the three practice tasks without a sighted helper; they can replay the tutorial.

### 3. Diagnostics command

**Why:** when a pilot user says “it is not working”, the coordinator needs facts, not guesses.

**How:**
- Add `VoiceCommand.diagnostics` and phrases (“diagnostics”, “status”, “check phone”).
- New `lib/core/diagnostics_service.dart` reads: app version, device model, Android version, camera/mic/location permission state, TTS availability for English/Hindi, speech-recognition availability, battery, thermal status, last error.
- Speak a compact summary; optionally export a text file with `share_plus`.
- Log the same summary locally.

**Acceptance:** a coordinator can diagnose the top five support issues in under two minutes.

### 4. Opt-in usage log for impact reporting

**Why:** Rotary and the NGO need numbers for their report. Do not add a server; keep it local.

**How:**
- New `lib/core/usage_log.dart`; JSON lines in the app support directory.
- Counters only: sessions, reads, object descriptions, refusals, errors, language, mode, app version, device model.
- Never store text, images, audio, or location.
- Ask consent during onboarding; a voice command can turn it off.
- Export via `share_plus`; rotate at 1 MB; add “delete my data”.
- Add a simple summary screen or spoken summary for the coordinator.

**Acceptance:** the endline report can state sessions, reads, errors, and active weeks without collecting personal data.

### 5. Battery and thermal policy

**Why:** object mode runs every 1.2 s; a 30-minute session may heat a budget phone.

**How:**
- Read battery level and thermal status through the existing native `cue/device` channel or `PowerManager.getCurrentThermalStatus()`.
- New `ThermalPolicy` in `lib/live/frame_pipeline.dart`: if thermal status is moderate/severe, raise `_objectMinGap` from 1.2 s to 2.5/4 s and reduce OCR cadence; announce once, not repeatedly.
- Warn at 15% and 5% battery; offer “pause camera”.
- Measure 30 minutes on a real budget phone before claiming efficiency.

**Acceptance:** 30 minutes of mixed use stays under 15% battery on the test phone and does not throttle in 10 minutes.

### 6. Audio focus and TalkBack coexistence

**Why:** Cue has its own TTS; TalkBack also speaks. Double speech makes the app unusable for screen-reader users.

**How:**
- Request transient audio focus on Android (`AudioManager.requestAudioFocus`) when speaking; abandon it after.
- Duck other audio instead of stopping it.
- Test with TalkBack on: double-tap activation, two-finger gestures, volume key, and TTS overlap.
- If TalkBack speaks over Cue, pause Cue’s TTS and resume after; never talk over a screen reader.
- Add a “TalkBack detected” first-run hint.

**Acceptance:** no double-speaking in a 15-minute TalkBack session; all core actions remain reachable.

### 7. Offline voice commands

**Why:** the demo and rural use cannot depend on a network.

**How:**
- First, test `speech_to_text` on three phones with the English and Hindi offline packs and airplane mode.
- If the offline recogniser is available, expose it and detect the missing-pack case; tell the user how to install it.
- If it is not, evaluate a small Vosk model with a grammar limited to the ~40 commands. This adds app size but removes the Google dependency.
- Always keep gesture fallbacks; never make voice the only path.

**Acceptance:** 20 core commands work offline on at least three phone models; a clear fallback exists when they do not.

---

## Priority 2 — differentiators (1–3 months)

### 8. Indian rupee recognition

**Why:** currency is one of the highest-value daily tasks for blind users, and Google Lookout only covers a few currencies.

**How:**
- New `lib/vision/currency_service.dart` with a small TFLite classifier for ₹10/20/50/100/200/500/2000.
- Collect 50–100 images per class in different light, angles, wear, and backgrounds; split train/validation by note, not by image.
- Add `Interpretation.currency`; handle it in `frame_pipeline` like object mode.
- Speak only above a confidence threshold; otherwise “I cannot tell which note this is.”
- Add Hindi labels and tests; check RBI reproduction guidelines and legal advice.
- Consider a fallback that reads the number printed on the note with OCR.

**Acceptance:** 90%+ accuracy on a held-out set in good light; honest refusal on unclear notes.

### 9. Document mode

**Why:** letters, bills, and forms are longer than one camera frame.

**How:**
- Use `google_mlkit_document_scanner` or a custom edge-detection/crop flow.
- Capture a full page, correct perspective, OCR, and read in order.
- Add multi-page capture and “read from here”.
- Save/share the recognised text only with user action.

**Acceptance:** a two-page letter is read in the correct order with fewer repeats than live mode.

### 10. Medicine-label mode

**Why:** the medicine label is the emotional core of the pitch.

**How:**
- A guided capture that zooms/crops the label, then OCR.
- Extract and repeat dosage lines, expiry date, and warnings; do not give medical advice.
- Say “I read this as…” and offer repeat; never infer a dose.
- Test with real strips, blister packs, and Hindi/English labels.

**Acceptance:** reads the expiry date and dosage line correctly on 20 real packages, with honest refusal on blur.

### 11. Low-vision mode

**Why:** not all users are totally blind; magnification and contrast are a large adjacent need.

**How:**
- Use the camera zoom, contrast, and colour inversion; large on-screen text.
- Add a simple gesture/voice entry; keep the audio path intact.
- Test with low-vision users, not only blind users.

**Acceptance:** a low-vision user can read a menu at arm’s length with the mode.

### 12. More Indian languages (frozen until English is validated)

**Why:** Hindi is a start, not the country.

**How:**
- Add `CueStrings` for Marathi, Tamil, Telugu, Bengali; map OCR scripts; check TTS/STT availability.
- Use professional/human review for safety-critical strings; do not ship machine-only translations for medicine instructions.
- Partner with local NGOs for translation and testing.

**Acceptance:** one new language is fully tested end-to-end with five native speakers before adding the next.

### 13. Trainer mode

**Why:** NGO staff need a visual dashboard to support users.

**How:**
- A hidden screen reachable by a three-finger tap or a long-press menu.
- Shows mode, last result, diagnostics, quick actions, and a “send report” button.
- Large text and high contrast; no dependency on the blind user’s gesture set.

**Acceptance:** a trainer can set up a phone and diagnose a user issue without a developer.

---

## Do not build yet

- Navigation or walking guidance. It is unsafe and invites overclaiming.
- Face recognition. Privacy and ethical risk; not needed for the pilot.
- Cloud AI. It breaks the offline/privacy story and adds cost.
- Accounts, social features, ads, gamification.
- A smart-glasses integration. Prove the phone first.

---

## Intuitive design rules for Cue

1. **One action = one earcon + one sentence.** The user should never wonder whether the phone heard them.
2. **Every gesture has a voice equivalent.** No hidden gesture is the only path.
3. **No dead ends.** Unbuilt modes do not appear in the swipe cycle; asking for one explicitly gets an honest answer.
4. **Acknowledge within 300 ms.** A short “heard” tone, then the result. If OCR takes longer, say “reading” after one second.
5. **Repeat, stop, and help always work.** These are the three safety valves.
6. **Errors say what happened, what to do, and how to get help.** “I could not get a location fix. Move near a window, then ask again.”
7. **Language switching confirms in the new language**, and refuses to half-switch if the voice is missing.
8. **The screen is for sighted helpers.** Keep the status panel readable, show the mode, and let it fade without stopping the work.
9. **Train the hesitation, not the feature list.** Watch five blind users; fix the moment they pause, not the thing you are proud of.
10. **Measure before claiming.** Cold start, first word, object latency, battery per 30 minutes, crash-free sessions.
