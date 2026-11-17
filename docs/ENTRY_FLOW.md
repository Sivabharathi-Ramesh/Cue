# Cue entry flow — recommendation

## The short answer

**Camera-first, reading-default, no home screen.** That is the right choice, and the shipping app already does it.

Two clarifications:

1. The app does **not** open `lib/modes/read_screen.dart`. It opens `lib/live/live_screen.dart`. The `modes/` screens are legacy stubs from an earlier architecture; they are unreachable.
2. The live screen starts in **Text** interpretation, so it feels like a reading screen. That is intentional: reading is the most common, highest-value, and safest first task.

What needs to change is not the order of screens. It is what happens **before** the camera on first launch, and what the app **remembers** between launches.

---

## Current flow

```
main()
  -> LanguageService.init()          // saved language, default English
  -> runApp(CueApp)
  -> LiveScreen
       -> FramePipeline(language)    // starts in Interpretation.text
       -> camera starts
       -> one-time spoken intro: "Cue is looking. Point the camera at text."
```

There is no home screen, no mode menu, no first-run language choice, and no memory of the last mode. Every launch starts in Text and speaks the Text intro.

The old `HomeScreen` (Read / Identify / Floor / Walk / Currency) is unreachable. Keep it out. A menu of five buttons is a wall for a blind user.

---

## Recommended flow

### First launch (once, 30–60 seconds)

1. Spoken English welcome: “Cue. Hold volume down and say read, or double-tap to read.”
2. English is the only language in this phase. Hindi remains in the build but is frozen, so there is no language question yet.
3. Three practice tasks, each confirmed with a distinct earcon:
   - Double-tap to read a label.
   - Hold volume-down and say “what is this?”
   - Say “help” to hear the controls.
4. “You’re ready. Cue will open straight into the camera next time.”
5. Store `onboarding_complete`.

If the user does nothing for ten seconds, continue in English. Never trap a user in onboarding.

A language choice is deliberately deferred until English is validated with real users.

### Every launch after that

1. Load language and last **built** mode.
2. Start the camera in that mode.
3. Speak a mode-appropriate intro:
   - Text: “Cue is looking. Point the camera at text.”
   - Object: “Cue is looking. Point the camera at an object.”
4. No menu. No splash screen. No “choose a mode.”

### In session

- Swipe sideways or say “text mode” / “object mode.”
- Only built modes appear in the swipe cycle. If the user explicitly asks for Banknote or Screen, answer honestly that it is not built.
- The status panel shows the current mode for sighted helpers.

---

## Why not a home screen?

- A blind user navigates by audio and memory. Every menu is another decision and another chance to get lost.
- The most common task is reading. It should be the default action, not a choice.
- Modes are a developer concept. The user thinks “read this” or “what is this?”, not “switch interpretation.”
- The app already has voice commands and four gestures. That is enough navigation.
- A visual home screen is useful for sighted trainers, not for users. Add a trainer mode later if needed; do not put it in the user’s path.

---

## What to remember

| State | Current | Recommended |
|---|---|---|
| Language | Persisted (`cue_language.json`), defaults to English | Keep, but freeze Hindi for this phase |
| Last mode | Not persisted | Persist, built modes only |
| Onboarding complete | One-time voice intro flag | Full onboarding flag |
| Reading speed | Check `AudioBus`/TTS service | Persist if not already |
| Consent for usage counts | None | Ask during onboarding |

---

## Implementation plan

### 1. Persist the last built mode (about 1 hour)

Create `lib/live/mode_service.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'scene_router.dart';

class ModeService {
  ModeService._();
  static final ModeService instance = ModeService._();

  final ValueNotifier<Interpretation> mode =
      ValueNotifier<Interpretation>(Interpretation.text);

  Future<void> init() async {
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return;
      final value = json['mode'];
      final found = Interpretation.values
          .where((m) => m.name == value && m.isBuilt)
          .firstOrNull;
      if (found != null) mode.value = found;
    } catch (_) {
      // Missing or corrupt means Text.
    }
  }

  Future<void> set(Interpretation value) async {
    if (!value.isBuilt) return;
    mode.value = value;
    try {
      final file = await _file();
      if (file == null) return;
      await file.writeAsString(jsonEncode({'mode': value.name}));
    } catch (_) {
      // Losing the preference is better than blocking the switch.
    }
  }

  Future<File?> _file() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/cue_mode.json');
    } catch (_) {
      return null;
    }
  }
}
```

Then:

- In `main()`, await `ModeService.instance.init()` alongside `LanguageService.instance.init()`.
- In `LiveScreen.initState()`, after creating `_pipeline`, call `_pipeline.setInterpretation(ModeService.instance.mode.value);` before `_prepareAndStart()`.
- In `_setInterpretation()`, call `unawaited(ModeService.instance.set(next));` for built modes only.
- In `_announceReady()`, choose the intro from the current interpretation. Add `lookingObject` and `lookingObjectIntro` to `CueStrings`.
- In `_changeInterpretation()`, skip unbuilt modes: loop `next`/`previous` until `isBuilt`.
- Add tests: persist/restore, corrupt file fallback, unbuilt mode never restored, swipe cycle only built modes.

**Acceptance:** switch to Object, force-close, reopen; the app starts in Object and says “Point the camera at an object.” Switch back to Text; the next launch is Text.

### 2. First-run onboarding (about 1–2 days)

- Replace `lib/core/voice_intro.dart` with `lib/core/onboarding_service.dart` (or extend it) that stores a step and a completion flag.
- Keep onboarding inside `LiveScreen` as a spoken overlay rather than a separate route, so the camera lifecycle does not change.
- On first launch, run the bilingual language prompt, then the three practice tasks.
- Every prompt has a gesture fallback and a ten-second default.
- Add voice commands “tutorial” and “skip tutorial.”
- Test with five blind users; the success criterion is completing the three tasks without sighted help.

### 3. Reading depth before more modes (next priority)

Reading is the right first mode, but it needs depth more than breadth:

- **Medicine label:** guided crop/zoom, read dosage and expiry, never give medical advice.
- **Document/letter:** full-page capture, perspective correction, multi-page reading in order.
- **Recovery:** if the text is unreadable, say what to change — closer, steadier, more light, rotate.
- **Hindi quality:** test real Hindi labels, not just clean printed pages.
- **TTS fallback:** if the Hindi voice is missing, explain how to install it or offer English.

Do these before Currency, Screen, or a home screen.

---

## What to say tomorrow

If someone asks “where is the home screen?”:

> “There isn’t one. For a blind user, a menu is a wall. The camera is the home screen. It opens ready to read, and one swipe or one sentence changes the mode.”

Then demo Text → Object → Hindi → failure case. That sequence tells the story better than a menu ever could.

## What not to change before the demo

- Do not add a home screen.
- Do not reorder the modes.
- Do not touch Hindi. No new Hindi strings, phrases, or voice testing.
- Do not add onboarding tonight.
- Do not add last-mode persistence tonight unless you can rebuild, run the tests, and reinstall by early evening.

Freeze the build. The entry flow is already the right shape; it needs polish after the pilot, not surgery before the meeting.
