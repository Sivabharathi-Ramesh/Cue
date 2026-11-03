import 'dart:async';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import '../core/audio_bus.dart';
import '../core/feedback.dart';
import '../core/text_similarity.dart';
import '../vision/frame_source.dart';
import '../vision/ocr_service.dart';
import 'aiming_coach.dart';
import 'frame_metrics.dart';
import 'stability_gate.dart';

/// The live loop: frame in, spoken result or aiming cue out.
///
/// This class knows nothing about widgets. It can therefore be reasoned about
/// (and tested) as a sequence of decisions: throttle, quality gate, OCR,
/// stability, speak, aim.
class FramePipeline {
  FramePipeline({required this.onResult, this.onCue});

  /// Called with the text that was actually spoken, for the sighted-helper
  /// caption on screen.
  final void Function(String text) onResult;

  /// Called when an aiming instruction is issued, for logging or the caption.
  final void Function(AimingCue cue)? onCue;

  static const Duration _minFrameGap = Duration(milliseconds: 320);
  static const Duration _staleAfter = Duration(milliseconds: 1400);

  /// Below this Laplacian variance a frame is treated as blurred.
  static const double _blurThreshold = 25;

  /// Below this mean absolute difference the scene is treated as unchanged.
  static const double _changeThreshold = 0.004;

  final FrameSampler _sampler = FrameSampler();
  final StabilityGate _stability = StabilityGate();
  final AimingCoach _coach = AimingCoach();

  DateTime _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOcr = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastSpokenAt;

  bool _busy = false;
  bool _manualRequested = false;
  int _generation = 0;

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
    _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastOcr = DateTime.fromMillisecondsSinceEpoch(0);
    _lastSpokenAt = null;
  }

  Future<void> _handle(CameraFrame frame) async {
    if (_busy) return;

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
    final tooBlurry = metrics.sharpness < _blurThreshold;
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
      final read = await OcrService.instance.readLiveFrame(
        nv21: frame.nv21,
        width: frame.image.width,
        height: frame.image.height,
        rotation: rotation,
      );
      if (kDebugMode) {
        debugPrint(
          'live: ocr ${watch.elapsedMilliseconds}ms '
          '${frame.image.width}x${frame.image.height} '
          'chars=${read.text.length}',
        );
      }

      // The camera was stopped, or a new session began, while OCR ran.
      if (generation != _generation) return;

      final text = speakable(read.text);
      final frameSize = rotatedSize(frame.image.width, frame.image.height, rotation);
      final layout = read.blocks.isEmpty
          ? null
          : TextLayout.fromRects(
              read.blocks.map((block) => block.boundingBox).toList(growable: false),
              frameSize,
              wordCount: _wordCount(text),
            );

      if (text.isEmpty) {
        _stability.reset();
      } else {
        _stability.add(text);
      }

      if (text.isNotEmpty && (manual || _stability.isStable)) {
        final spoken = AudioBus.instance.speakResult(text, force: manual);
        if (spoken) {
          _lastSpokenAt = DateTime.now();
          onResult(text);
          unawaited(Feedback.instance.found());
        }
      } else if (manual) {
        unawaited(Feedback.instance.notSure());
        unawaited(
          AudioBus.instance.say(
            'I am not sure. I cannot see text. Hold steady and point at the '
            'page.',
            priority: SpeechPriority.alert,
          ),
        );
      }

      if (!manual) {
        _maybeAim(metrics, layout, DateTime.now(), text);
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

  void _maybeAim(
    FrameMetrics metrics,
    TextLayout? layout,
    DateTime now,
    String text,
  ) {
    final recentlySpoken = _lastSpokenAt != null &&
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
    unawaited(Feedback.instance.aimProblem(pitch: cue.toneHz, pan: cue.pan));
    unawaited(
      AudioBus.instance.say(cue.speech, priority: SpeechPriority.navigation),
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
