import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

import 'audio_bus.dart';

/// Every non-speech signal the app makes.
///
/// Section 7 of the specification gives each state its own sound and
/// vibration. Keeping them in one class means the live screen cannot invent
/// a new beep pattern on a whim, and every signal is documented in one place.
///
/// Tones are generated natively on Android through the `cue/feedback` channel
/// (a short AudioTrack sine wave). No audio package is needed, and a rising
/// pitch — which FR-04 asks for — is possible. On platforms without the
/// channel the class falls back to the system click.
class Feedback {
  Feedback._();

  static final Feedback instance = Feedback._();

  static const MethodChannel _channel = MethodChannel('cue/feedback');

  bool _hasVibrator = true;

  Future<void> init() async {
    try {
      _hasVibrator = await Vibration.hasVibrator();
    } catch (_) {
      _hasVibrator = false;
    }
  }

  /// FR-01: short rising tone and one pulse when the camera is live.
  Future<void> ready() async {
    await _tone(520, 70, 0.22);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await _tone(780, 90, 0.22);
    await _vibrate(duration: 45, iosLevel: 'medium');
  }

  /// FR-03: clear beep plus one pulse when a result is spoken.
  Future<void> found() async {
    await _tone(880, 60, 0.18);
    await _vibrate(duration: 55, iosLevel: 'medium');
  }

  /// FR-09 / manual read with nothing usable: low double tone, two pulses.
  Future<void> notSure() async {
    await _tone(330, 80, 0.2);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await _tone(260, 120, 0.2);
    await _vibrate(pattern: const <int>[0, 60, 60, 60], iosLevel: 'light');
  }

  /// FR-04: a distinct tone accompanies an aiming instruction.
  ///
  /// [pitch] separates the six problems, and [pan] places "move left" in the
  /// left ear and "move right" in the right ear.
  Future<void> aimProblem({double pitch = 300, double pan = 0}) async {
    await _tone(pitch, 90, 0.2, pan: pan);
  }

  /// FR-12: falling tone and one long pulse.
  Future<void> paused() async {
    await _tone(420, 80, 0.2);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _tone(280, 120, 0.2);
    await _vibrate(duration: 130, iosLevel: 'heavy');
  }

  /// Error: buzz and three pulses, then a plain-language explanation.
  Future<void> error() async {
    await _tone(200, 150, 0.25);
    await _vibrate(
      pattern: const <int>[0, 80, 50, 80, 50, 80],
      iosLevel: 'heavy',
    );
  }

  /// Voice command: Cue is ready to listen.
  ///
  /// Rising, so it cannot be confused with the falling "paused" or the low
  /// "not heard" signal. No speech: the microphone would hear it.
  Future<void> listening() async {
    await _tone(620, 60, 0.2);
    await Future<void>.delayed(const Duration(milliseconds: 70));
    await _tone(930, 80, 0.2);
    await _vibrate(duration: 40, iosLevel: 'medium');
  }

  /// Voice command: the words were understood.
  Future<void> heard() async {
    await _tone(1100, 45, 0.18);
    await _vibrate(duration: 25, iosLevel: 'light');
  }

  /// Voice command: nothing usable was heard.
  Future<void> notHeard() async {
    await _tone(300, 70, 0.2);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _tone(220, 100, 0.2);
    await _vibrate(pattern: const <int>[0, 40, 50, 40], iosLevel: 'light');
  }

  /// Confirmation that a gesture was received.
  Future<void> gesture() => _vibrate(duration: 30, iosLevel: 'light');

  /// Searching: soft slow tick. No vibration, no speech.
  Future<void> tick() => _tone(660, 40, 0.06);

  DateTime? _lastToneAt;

  /// FR-04: pitch rises as more of the frame is covered by text.
  Future<void> toneFor(double coverage) async {
    if (AudioBus.instance.speaking.value) return;

    final now = DateTime.now();
    if (_lastToneAt != null &&
        now.difference(_lastToneAt!) < const Duration(milliseconds: 1200)) {
      return;
    }
    _lastToneAt = now;

    // Page text rarely covers more than a fifth of the frame; map that range
    // onto 400-1200 Hz so the change is audible rather than shrill.
    final level = (coverage / 0.2).clamp(0.0, 1.0);
    await _tone(400 + 800 * level, 70, 0.16);
  }

  Future<void> _vibrate({
    int duration = 50,
    List<int>? pattern,
    // On iOS the vibration package ignores duration/pattern.
    // 'light', 'medium' (default), 'heavy', or 'selection'.
    String iosLevel = 'medium',
  }) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Use Flutter's HapticFeedback which maps to UIImpactFeedbackGenerator.
      try {
        switch (iosLevel) {
          case 'light':
            await HapticFeedback.lightImpact();
          case 'heavy':
            await HapticFeedback.heavyImpact();
          case 'selection':
            await HapticFeedback.selectionClick();
          default:
            await HapticFeedback.mediumImpact();
        }
      } catch (_) {}
      return;
    }

    if (!_hasVibrator) return;
    try {
      if (pattern != null) {
        await Vibration.vibrate(pattern: pattern);
      } else {
        await Vibration.vibrate(duration: duration);
      }
    } catch (_) {
      // A missing vibrator must never break the reading flow.
    }
  }

  Future<void> _tone(
    double frequency,
    int durationMs,
    double volume, {
    double pan = 0,
  }) async {
    try {
      await _channel.invokeMethod<void>('tone', <String, dynamic>{
        'frequency': frequency,
        'durationMs': durationMs,
        'volume': volume,
        'pan': pan,
      });
    } on MissingPluginException {
      // iOS has no cue/feedback channel yet. A system click is an honest
      // fallback, not a silent failure.
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    } catch (_) {
      // Audio is feedback, never a reason to crash a reading.
    }
  }
}
