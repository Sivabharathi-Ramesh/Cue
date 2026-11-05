import 'dart:async';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import '../core/audio_bus.dart';
import '../core/cue_language.dart';
import '../core/cue_strings.dart';
import '../core/feedback.dart';
import '../core/text_similarity.dart';
import '../vision/frame_source.dart';
import '../vision/ocr_service.dart';
import 'aiming_coach.dart';
import 'frame_metrics.dart';
import 'reading_quality.dart';
import 'scene_router.dart';
import 'stability_gate.dart';

/// The live loop: frame in, spoken result or aiming cue out.
///
/// This class knows nothing about widgets. It can therefore be reasoned about
/// (and tested) as a sequence of decisions: throttle, quality gate, OCR,
/// stability, speak, aim.
class FramePipeline {
  FramePipeline({
    required this.onResult,
    this.onCue,
    this.onLanguageDetected,
    CueLanguage language = CueLanguage.english,
  }) : _language = language; // ignore: prefer_initializing_formals

  /// Called with the text that was actually spoken, for the sighted-helper
  /// caption on screen.
  final void Function(String text) onResult;

  /// Called when an aiming instruction is issued, for logging or the caption.
  final void Function(AimingCue cue)? onCue;

  /// Called when the pipeline detects a script that differs from the current
  /// language setting.
  ///
  /// The callback must switch voice output and save the preference, then
  /// return true. Returning false tells the pipeline to stay on the old
  /// script, which is what happens when the phone has no Hindi voice.
  final Future<bool> Function(CueLanguage detected)? onLanguageDetected;

  CueLanguage _language;

  CueLanguage get language => _language;

  CueStrings get _strings => CueStrings(_language);

  static const Duration _minFrameGap = Duration(milliseconds: 320);
  static const Duration _staleAfter = Duration(milliseconds: 1400);

  /// Below this mean absolute difference the scene is treated as unchanged.
  static const double _changeThreshold = 0.004;

  /// Consecutive untrusted readings before the app admits it cannot read them.
  ///
  /// One bad frame is normal: motion blur, a passing shadow, a page turning.
  /// Three in a row means the marks in view are genuinely not readable, which
  /// is the handwriting case. Saying so immediately would interrupt the user
  /// every time the camera nudged.
  static const int _untrustedBeforeSpeaking = 3;

  /// Minimum gap between "I cannot read these marks" sentences, so pointing at
  /// handwriting does not produce the same apology forever.
  static const Duration _honestyCooldown = Duration(seconds: 25);

  /// Consecutive frames without words before saying there is something in view
  /// that Cue cannot identify.
  ///
  /// The same reasoning as [_untrustedBeforeSpeaking] applies: one wordless
  /// frame is a shadow or a camera nudge, three is a scene.
  static const int _notTextBeforeSpeaking = 3;

  /// Minimum gap between "I see something..." sentences.
  static const Duration _notTextCooldown = Duration(seconds: 20);

  final FrameSampler _sampler = FrameSampler();
  final StabilityGate _stability = StabilityGate();
  final AimingCoach _coach = AimingCoach();
  final SceneRouter _router = const SceneRouter();

  DateTime _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOcr = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastSpokenAt;

  bool _busy = false;
  bool _manualRequested = false;
  int _generation = 0;

  /// How many readings in a row were refused by the honesty gate.
  int _untrustedStreak = 0;

  /// When the "I cannot read these marks" sentence was last spoken.
  DateTime? _lastHonestyAt;

  /// How many frames in a row contained no words at all.
  int _notTextStreak = 0;

  /// When "I see something, but I cannot tell what it is" was last spoken.
  DateTime? _lastNotTextAt;

  /// The last time the pipeline tried the other script because the selected
  /// recogniser found nothing. Prevents a wasted second OCR pass every frame.
  DateTime? _lastAutoDetectAt;

  /// When the user chose a language explicitly. Auto-detection stays quiet for
  /// a while afterwards, so saying "English" is not immediately undone by the
  /// page still being in Hindi.
  DateTime? _manualLanguageAt;

  /// What the user last told Cue to look for. Text is the only built handler.
  Interpretation _interpretation = Interpretation.text;

  Interpretation get interpretation => _interpretation;

  /// Switches interpretation and lets the next frame be analysed immediately.
  ///
  /// Called by the side-swipe gesture. The caller is responsible for telling
  /// the user which mode was chosen; this method only changes state.
  void setInterpretation(Interpretation value) {
    if (value == _interpretation) return;
    _interpretation = value;
    _stability.reset();
    _untrustedStreak = 0;
    _notTextStreak = 0;
    _lastHonestyAt = null;
    _lastNotTextAt = null;
    _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastOcr = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Switches the OCR script and clears every frame-to-frame gate.
  ///
  /// Text from the old script must not be compared with text from the new one:
  /// a Hindi page and an English page have no tokens in common, and the
  /// stability gate would otherwise ask for an extra confirmation.
  void setLanguage(CueLanguage value) {
    if (value == _language) return;
    _language = value;
    _manualLanguageAt = DateTime.now();
    reset();
  }

  /// Entry point wired to the camera stream. Fire-and-forget on purpose: the
  /// camera must never be blocked while OCR runs.
  void handleFrame(CameraFrame frame) {
    unawaited(_handle(frame));
  }

  /// Double-tap / "read now": ignore the change gate and the stability gate.
  void requestManualRead() {
    _manualRequested = true;
  }

  /// Invalidates in-flight work when the camera stops.
  void reset() {
    _generation++;
    _sampler.reset();
    _stability.reset();
    _coach.reset();
    _busy = false;
    _manualRequested = false;
    _untrustedStreak = 0;
    _lastHonestyAt = null;
    _notTextStreak = 0;
    _lastNotTextAt = null;
    _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastOcr = DateTime.fromMillisecondsSinceEpoch(0);
    _lastSpokenAt = null;
    _lastAutoDetectAt = null;
  }

  Future<void> _handle(CameraFrame frame) async {
    if (_busy) return;

    // Unbuilt interpretations do not touch the camera or the recogniser. A
    // manual read still gets an answer, because the user asked for one; a
    // frame nobody asked about gets silence rather than a guess.
    if (_interpretation != Interpretation.text) {
      if (_manualRequested) {
        _manualRequested = false;
        _sayUnbuiltMode();
      }
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastAttempt) < _minFrameGap) return;
    _lastAttempt = now;

    final generation = _generation;
    final metrics = _sampler.sample(frame.image);
    final manual = _manualRequested;
    _manualRequested = false;

    // A stale scene is analysed at least once every 1.4 s even if the change
    // gate says nothing moved. Without this, a perfectly still page would
    // never be read, and a permanently soft camera would look dead.
    final stale = now.difference(_lastOcr) > _staleAfter;
    final tooBlurry = metrics.isTooBlurry;
    final unchanged = metrics.change < _changeThreshold;

    if (!manual && !stale && (tooBlurry || unchanged)) {
      // Still worth telling the user it is too dark, even though OCR is
      // skipped. This is the one cue that does not need recognised text.
      if (metrics.isTooDark) {
        _maybeAim(metrics, null, now, '');
      }
      return;
    }

    _busy = true;
    _lastOcr = now;

    try {
      final rotation = rotationDegrees(
        frame.description,
        frame.deviceOrientation,
      );
      final watch = Stopwatch()..start();
      OcrRead read = await OcrService.instance.readLiveFrame(
        nv21: frame.nv21,
        width: frame.image.width,
        height: frame.image.height,
        rotation: rotation,
        bytesPerRow: frame.bytesPerRow,
        language: _language,
      );

      // A stop/resume while OCR was queued cancels everything that follows,
      // including the language-switch choice below.
      if (generation != _generation) return;

      // Script auto-detection: if the selected recogniser found nothing, try
      // the other script once. A blind user cannot see that they are holding a
      // Hindi page while Cue is set to English, so this is the one place where
      // guessing is safer than silence.
      //
      // The switch is awaited: speaking Devanagari with the old English voice
      // would be worse than waiting a moment for the new voice.
      final speaking = AudioBus.instance.speaking.value;
      final lastAuto = _lastAutoDetectAt;
      final lastManual = _manualLanguageAt;
      final autoDetectAllowed =
          (lastAuto == null ||
              now.difference(lastAuto) > const Duration(seconds: 15)) &&
          (lastManual == null ||
              now.difference(lastManual) > const Duration(seconds: 30)) &&
          !speaking &&
          !AudioBus.instance.hasReading;

      if (read.text.trim().isEmpty &&
          !metrics.isTooBlurry &&
          autoDetectAllowed) {
        _lastAutoDetectAt = now;
        final other = _language == CueLanguage.english
            ? CueLanguage.hindi
            : CueLanguage.english;
        final otherRead = await OcrService.instance.readLiveFrame(
          nv21: frame.nv21,
          width: frame.image.width,
          height: frame.image.height,
          rotation: rotation,
          bytesPerRow: frame.bytesPerRow,
          language: other,
        );

        if (otherRead.text.trim().isNotEmpty &&
            looksLikeText(speakable(otherRead.text))) {
          final switched = await onLanguageDetected?.call(other) ?? false;
          if (switched) {
            if (kDebugMode) {
              debugPrint('live: auto-detected ${other.label} script');
            }
            _language = other;
            read = otherRead;
          }
        }
      }
      // The switch itself is awaited, so the camera may have stopped while we
      // waited for the voice. Do not speak from a superseded session.
      if (generation != _generation) return;

      final text = speakable(read.text);
      final quality = ReadingQuality.of(text, read.confidence);

      if (kDebugMode) {
        debugPrint(
          'live: ocr ${watch.elapsedMilliseconds}ms '
          '${frame.image.width}x${frame.image.height} '
          'chars=${read.text.length} '
          'conf=${quality.confidence?.toStringAsFixed(2) ?? 'n/a'} '
          'tier=${quality.tier.name}'
          '${quality.reason == null ? '' : ' (${quality.reason})'}',
        );
      }

      final scene = _router.decide(metrics: metrics, text: text);
      if (kDebugMode) {
        debugPrint('live: scene $scene');
      }

      // A bright, sharp frame with no words is a scene, not a page: say so
      // once, honestly, instead of letting the aiming coach keep asking for
      // text that is not there. Aiming is skipped here for the same reason;
      // darkness is classified as unclear and handled by the aiming path.
      if (scene.kind == SceneKind.notText && text.isEmpty) {
        _stability.reset();
        _notTextStreak++;
        _maybeSpeakNotText(manual: manual);
        return;
      }

      // Any words at all mean the no-words streak is over, even if the marks
      // turn out to be unreadable handwriting.
      _notTextStreak = 0;

      final frameSize = rotatedSize(
        frame.image.width,
        frame.image.height,
        rotation,
      );
      final layout = read.blocks.isEmpty
          ? null
          : TextLayout.fromRects(
              read.blocks
                  .map((block) => block.boundingBox)
                  .toList(growable: false),
              frameSize,
              wordCount: _wordCount(text),
            );

      if (kDebugMode && layout != null) {
        debugPrint(
          'live: aim centerX=${layout.centerX.toStringAsFixed(2)} '
          'coverage=${layout.coverage.toStringAsFixed(3)} '
          'height=${layout.heightRatio.toStringAsFixed(2)} '
          'words=${layout.wordCount} rotation=$rotation '
          'frame=${frameSize.width.toInt()}x${frameSize.height.toInt()}',
        );
      }

      // Any tier except refusal may be heard. An uncertain result is useful,
      // but only after the app says clearly that it may be wrong.
      final tier = quality.tier;
      final uncertain = tier == ReadingTier.uncertain;
      final readable = tier != ReadingTier.refused;

      if (readable) {
        _untrustedStreak = 0;
        _stability.add(text);

        if (manual || _stability.isStable) {
          final spoken = AudioBus.instance.speakResult(
            text,
            force: manual,
            uncertain: uncertain,
          );
          if (spoken) {
            _lastSpokenAt = DateTime.now();
            if (kDebugMode) {
              debugPrint(
                'live: speak chars=${text.length} manual=$manual tier=${tier.name}',
              );
            }
            onResult(AudioBus.labelReading(text, uncertain: uncertain));
            unawaited(
              uncertain
                  ? Feedback.instance.notSure()
                  : Feedback.instance.found(),
            );
          }
        }
      } else {
        _stability.reset();

        if (text.isEmpty) {
          _untrustedStreak = 0;
          if (manual) {
            unawaited(Feedback.instance.notSure());
            unawaited(
              AudioBus.instance.say(
                _strings.notSureNoText,
                priority: SpeechPriority.alert,
              ),
            );
          }
        } else {
          // There are marks in view, but they are not words the app can
          // honestly read. This is the handwriting case.
          _untrustedStreak++;
          _maybeRefuseReading(manual: manual);
        }
      }

      if (!manual) {
        _maybeAim(metrics, layout, DateTime.now(), readable ? text : '');
      }
    } catch (_) {
      // One bad frame must never take the live screen down. The next frame
      // gets another chance.
    } finally {
      // reset() already unlocked the pipeline; an old analysis finishing late
      // must not unlock a newer one that is still running.
      if (generation == _generation) _busy = false;
    }
  }

  /// Answers a manual read in a mode whose handler has not been built.
  ///
  /// The swipe itself is announced by the live screen. This is for the case
  /// where the user double-taps anyway: silence would look like a broken app.
  void _sayUnbuiltMode() {
    unawaited(
      AudioBus.instance.say(
        _strings.notBuilt(_strings.modeName(_interpretation.label)),
        priority: SpeechPriority.alert,
      ),
    );
  }

  /// Says, honestly, that there is something in view but it is not words.
  ///
  /// FR-05's fallback. It waits for a few consecutive wordless frames so a
  /// passing shadow does not trigger it, and then stays quiet for a while.
  void _maybeSpeakNotText({required bool manual}) {
    if (AudioBus.instance.isMuted) return;
    final now = DateTime.now();

    if (!manual) {
      if (_notTextStreak < _notTextBeforeSpeaking) return;
      final last = _lastNotTextAt;
      if (last != null && now.difference(last) < _notTextCooldown) return;
    }

    _lastNotTextAt = now;
    // Treat it like speech for aiming purposes: do not chirp a framing tone
    // over the top of the sentence the user is listening to.
    _lastSpokenAt = now;

    if (kDebugMode) {
      debugPrint('live: not-text manual=$manual streak=$_notTextStreak');
    }

    unawaited(Feedback.instance.notSure());
    unawaited(
      AudioBus.instance.say(
        _strings.somethingThere,
        priority: SpeechPriority.alert,
      ),
    );
  }

  /// Says, honestly, that there are marks but no readable words.
  ///
  /// A blind user cannot check a wrong reading, so guessing is worse than
  /// refusing. The manual path always answers because the user asked; the
  /// automatic path waits for a few consecutive failures and then keeps quiet
  /// for a while.
  void _maybeRefuseReading({required bool manual}) {
    if (AudioBus.instance.isMuted) return;
    final now = DateTime.now();

    if (!manual) {
      if (_untrustedStreak < _untrustedBeforeSpeaking) return;
      final last = _lastHonestyAt;
      if (last != null && now.difference(last) < _honestyCooldown) return;
    }

    _lastHonestyAt = now;
    // Treat it like speech for aiming purposes: do not chirp a framing tone
    // over the top of the sentence the user is listening to.
    _lastSpokenAt = now;

    if (kDebugMode) {
      debugPrint(
        'live: refuse reading manual=$manual streak=$_untrustedStreak',
      );
    }

    unawaited(Feedback.instance.notSure());
    unawaited(
      AudioBus.instance.say(
        _strings.marksNotReadable,
        priority: SpeechPriority.alert,
      ),
    );
  }

  void _maybeAim(
    FrameMetrics metrics,
    TextLayout? layout,
    DateTime now,
    String text,
  ) {
    // The microphone is open. Keep both the tone and the spoken cue out of it.
    if (AudioBus.instance.isMuted) return;
    // A sentence is being read. Framing tones are not useful then.
    if (AudioBus.instance.reading.value) return;

    final recentlySpoken =
        _lastSpokenAt != null &&
        now.difference(_lastSpokenAt!) < const Duration(seconds: 6);

    final cue = _coach.evaluate(
      brightness: metrics.brightness,
      layout: layout,
      now: now,
      recentlySpoken: recentlySpoken,
    );

    // A page that has already been read does not need a framing tone repeating
    // at the user every second. The dedupe rule decides that, so the tone and
    // the voice agree on what counts as "new".
    final last = AudioBus.instance.lastResult;
    final alreadyRead =
        text.isNotEmpty && last != null && newTokenRatio(last, text) < 0.35;

    if (cue == null) {
      // No problem to report: if there is unread text in view and nothing is
      // being spoken, the pitch tracks how much of the frame is covered. That
      // is the "tone rises as more text enters the frame" cue from FR-04.
      if (!recentlySpoken &&
          !alreadyRead &&
          layout != null &&
          layout.wordCount > 0) {
        unawaited(Feedback.instance.toneFor(layout.coverage));
      }
      return;
    }

    onCue?.call(cue);
    if (kDebugMode) {
      debugPrint(
        'live: cue ${cue.name} centerX=${layout?.centerX.toStringAsFixed(2) ?? "n/a"}',
      );
    }
    unawaited(Feedback.instance.aimProblem(pitch: cue.toneHz, pan: cue.pan));
    unawaited(
      AudioBus.instance.say(
        cue.speechFor(_language),
        priority: SpeechPriority.navigation,
      ),
    );
  }

  int _wordCount(String text) {
    if (text.trim().isEmpty) return 0;
    return text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
  }
}

/// Clockwise rotation needed to make the frame upright for ML Kit.
int rotationDegrees(
  CameraDescription description,
  DeviceOrientation orientation,
) {
  final deviceDegrees = switch (orientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };

  final sensor = description.sensorOrientation;
  if (description.lensDirection == CameraLensDirection.front) {
    return (sensor + deviceDegrees) % 360;
  }
  return (sensor - deviceDegrees + 360) % 360;
}

/// Size of the image after ML Kit applies [rotation].
Size rotatedSize(int width, int height, int rotation) {
  return rotation % 180 == 0
      ? Size(width.toDouble(), height.toDouble())
      : Size(height.toDouble(), width.toDouble());
}
