import 'dart:async';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import '../core/audio_bus.dart';
import '../core/cue_language.dart';
import '../core/cue_strings.dart';
import '../core/feedback.dart';
import '../core/motion_monitor.dart';
import '../core/text_similarity.dart';
import '../core/tts_service.dart';
import '../vision/frame_source.dart';
import '../vision/ocr_service.dart';
import '../vision/camera_frame_encoder.dart';
import '../vision/detected_object.dart';
import '../vision/object_detect_service.dart';
import '../vision/object_tracker.dart';
import '../vision/object_colour.dart';
import '../core/object_labels.dart';
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
    CueLanguage language = CueLanguage.english,
  }) : _language = language; // ignore: prefer_initializing_formals

  /// Called with the text that was actually spoken, for the sighted-helper
  /// caption on screen.
  final void Function(String text) onResult;

  /// Called when an aiming instruction is issued, for logging or the caption.
  final void Function(AimingCue cue)? onCue;

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

  /// Consecutive frames without words before saying there is something in view
  /// that Cue cannot identify.
  ///
  /// The same reasoning as [_untrustedBeforeSpeaking] applies: one wordless
  /// frame is a shadow or a camera nudge, three is a scene.
  static const int _notTextBeforeSpeaking = 3;

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

  /// The last time the pipeline tried the other script. This prevents a
  /// second OCR pass on every frame on poor lighting.
  DateTime? _lastAutoDetectAt;

  /// When "I see something, but I cannot tell what it is" was last spoken.
  DateTime? _lastNotTextAt;

  /// Tilt and steadiness hints are useful but must never nag.
  DateTime? _lastTiltCueAt;
  DateTime? _lastStillCueAt;
  DateTime? _movingSince;

  /// Set once the user (or the saved setting) has been told the chosen
  /// script's voice is missing. Silence beats repeating the same warning.
  bool _voiceMissingAnnounced = false;

  /// Minimum gap between object-detection passes in Object mode.
  ///
  /// Short enough that two passes (the confirmation) finish in about two and
  /// a half seconds, long enough that the phone does not cook.
  static const Duration _objectMinGap = Duration(milliseconds: 1200);

  /// How long the same scene stays quiet before being described again.
  static const Duration _objectRepeatGap = Duration(seconds: 8);

  /// Requires an object to be seen twice before Cue trusts it.
  final ObjectTracker _objectTracker = ObjectTracker();

  /// When the object mode last analysed a frame.
  DateTime _lastObjectAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// TEMP DIAG: rate-limits the object-skip reason line.
  DateTime _lastObjectDiagAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// What was last described: names, directions and distance bands.
  String _lastObjectSignature = '';

  /// When objects were last announced, so the same scene is not repeated.
  DateTime? _lastObjectSpokenAt;

  /// The most recent detections, kept so a follow-up question about a side can
  /// reuse work the camera has already done.
  List<DetectedObject> _lastObjects = const <DetectedObject>[];

  List<DetectedObject> get lastObjects => _lastObjects;

  /// Whether developer inspection mode is enabled.
  ///
  /// When true, frame detection rate in object mode is faster to provide
  /// smooth real-time bounding box visualization, and all detected objects
  /// are exposed via [detectedObjects].
  bool developerMode = false;

  /// Live detected objects for visual inspection (e.g. developer overlays).
  final ValueNotifier<List<DetectedObject>> detectedObjects =
      ValueNotifier<List<DetectedObject>>(const <DetectedObject>[]);

  /// A pending "what colour is this" request, answered on the next frame.
  Completer<ColourReading?>? _colourRequest;

  /// A pending "what is on my left/right" request, answered on the next frame.
  Completer<DetectedObject?>? _objectOnRequest;
  ObjectDirection? _objectOnSide;

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
    detectedObjects.value = const <DetectedObject>[];
    _stability.reset();
    _untrustedStreak = 0;
    _notTextStreak = 0;
    _lastHonestyAt = null;
    _lastNotTextAt = null;
    _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastOcr = DateTime.fromMillisecondsSinceEpoch(0);
    _lastObjectAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastObjectSignature = '';
    _lastObjectSpokenAt = null;
    _lastObjects = const <DetectedObject>[];
    _objectTracker.reset();
  }

  /// Switches the OCR script and clears every frame-to-frame gate.
  ///
  /// Text from the old script must not be compared with text from the new one:
  /// a Hindi page and an English page have no tokens in common, and the
  /// stability gate would otherwise ask for an extra confirmation.
  void setLanguage(CueLanguage value) {
    if (value == _language) return;
    _language = value;
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

  /// The colour in the middle of the view, sampled from a fresh frame.
  ///
  /// Resolves to null when the frame could not be decoded or the request timed
  /// out. The answer is deliberately about the *middle* of the view: naming
  /// one colour for a whole scene would be a guess.
  Future<ColourReading?> colourInView({
    Duration timeout = const Duration(seconds: 5),
  }) {
    final pending = _colourRequest;
    if (pending != null) return pending.future;

    final completer = Completer<ColourReading?>();
    _colourRequest = completer;
    Timer(timeout, () {
      if (!identical(_colourRequest, completer)) return;
      _colourRequest = null;
      if (!completer.isCompleted) completer.complete(null);
    });
    return completer.future;
  }

  /// The nearest recognised object on [side], found from a fresh frame.
  ///
  /// Works in any mode: the user asked a direct vision question, so the
  /// detector is run even when text mode is active. Resolves to null when
  /// nothing plausible is there.
  Future<DetectedObject?> objectOn(
    ObjectDirection side, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    final pending = _objectOnRequest;
    if (pending != null) return pending.future;

    final completer = Completer<DetectedObject?>();
    _objectOnRequest = completer;
    _objectOnSide = side;
    Timer(timeout, () {
      if (!identical(_objectOnRequest, completer)) return;
      _objectOnRequest = null;
      _objectOnSide = null;
      if (!completer.isCompleted) completer.complete(null);
    });
    return completer.future;
  }

  /// Invalidates in-flight work when the camera stops.
  void reset() {
    _generation++;
    detectedObjects.value = const <DetectedObject>[];
    _sampler.reset();
    _stability.reset();
    _coach.reset();
    _busy = false;
    _manualRequested = false;
    _untrustedStreak = 0;
    _lastHonestyAt = null;
    _notTextStreak = 0;
    _lastNotTextAt = null;
    _lastTiltCueAt = null;
    _lastStillCueAt = null;
    _movingSince = null;
    _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastOcr = DateTime.fromMillisecondsSinceEpoch(0);
    _lastSpokenAt = null;
    _lastAutoDetectAt = null;
    _lastObjectAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastObjectSignature = '';
    _lastObjectSpokenAt = null;
    _lastObjects = const <DetectedObject>[];
    _objectTracker.reset();
    _cancelQuestions();
  }

  Future<void> _handle(CameraFrame frame) async {
    if (_busy) return;

    final generation = _generation;
    final now = DateTime.now();

    // Answer any pending colour request using this frame.
    if (_colourRequest != null) {
      final req = _colourRequest!;
      _colourRequest = null;
      _busy = true;
      try {
        final reading = await _sampleCentreColour(frame);
        if (!req.isCompleted) req.complete(reading);
      } catch (_) {
        if (!req.isCompleted) req.complete(null);
      } finally {
        if (generation == _generation) _busy = false;
      }
      return;
    }

    // A moving phone produces blurred frames. Reading them wastes work and
    // makes the object detector guess, so wait for the hand to settle. Manual
    // reads are the user asking anyway, so they always go through.
    if (!_manualRequested && MotionMonitor.instance.isMoving) {
      _noteMovement(now);
      return;
    }
    _movingSince = null;

    // Object mode: the camera feeds YOLO instead of the text recogniser.
    if (_interpretation == Interpretation.object || _objectOnRequest != null) {
      final manual = _manualRequested || _objectOnRequest != null;
      _manualRequested = false;

      final canNarrate =
          !AudioBus.instance.hasReading &&
          !AudioBus.instance.speaking.value &&
          !AudioBus.instance.isMuted;
      final due = now.difference(_lastObjectAt) >= _objectMinGap;
      final devDue =
          developerMode &&
          now.difference(_lastObjectAt) >= const Duration(milliseconds: 250);

      if (!manual && !devDue && (!due || !canNarrate)) {
        if (kDebugMode &&
            now.difference(_lastObjectDiagAt) > const Duration(seconds: 3)) {
          _lastObjectDiagAt = now;
          debugPrint(
            'live: object skip due=$due narrate=$canNarrate '
            'muted=${AudioBus.instance.isMuted} '
            'speaking=${AudioBus.instance.speaking.value} '
            'reading=${AudioBus.instance.hasReading} '
            'moving=${MotionMonitor.instance.isMoving}',
          );
        }
        return;
      }

      _busy = true;
      try {
        await _detectObjects(frame, manual: manual, generation: generation);
      } finally {
        if (generation == _generation) _busy = false;
      }
      return;
    }

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

    if (now.difference(_lastAttempt) < _minFrameGap) return;
    _lastAttempt = now;
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
      } else if (tooBlurry) {
        _maybeTiltCue(frame.deviceOrientation, now);
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
      // The app's language is the saved preference. The script being read may
      // differ from this for one frame; that does not change the app.
      CueLanguage readerLanguage = _language;
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

      // Script auto-detection: if the selected recogniser returned nothing
      // useful, try the other script. The app decides this by itself because
      // a blind user cannot see that they are holding the other script.
      final speaking = AudioBus.instance.speaking.value;
      final lastAuto = _lastAutoDetectAt;
      final autoDetectAllowed =
          (lastAuto == null ||
              now.difference(lastAuto) > const Duration(seconds: 15)) &&
          !speaking &&
          !AudioBus.instance.hasReading;

      final selectedSpeakable = speakable(read.text);
      final selectedReadable =
          read.text.trim().isNotEmpty && looksLikeText(selectedSpeakable);
      final mostlyDevanagari = _devanagariFraction(read.text) > 0.15;
      final fewWords = _wordCount(selectedSpeakable) <= 2;
      final latinLooksEnglish = looksLikeEnglishText(selectedSpeakable);
      final tryOther =
          (!selectedReadable ||
              mostlyDevanagari ||
              fewWords ||
              !latinLooksEnglish) &&
          !metrics.isTooBlurry &&
          autoDetectAllowed;

      if (tryOther) {
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
          final previousVoice = TtsService.instance.language;
          if (await _ensureReadingVoice(other)) {
            if (kDebugMode) {
              debugPrint('live: auto-detected ${other.label} script');
            }
            if (previousVoice != other) {
              unawaited(
                AudioBus.instance.say(
                  other.isHindi
                      ? _strings.hindiDetected
                      : _strings.englishDetected,
                  priority: SpeechPriority.navigation,
                ),
              );
            }
            readerLanguage = other;
            read = otherRead;
          }
        }
      }
      // The switch itself is awaited, so the camera may have stopped while we
      // waited for the voice. Do not speak from a superseded session.
      if (generation != _generation) return;

      if (read.text.trim().isNotEmpty) {
        final voiceReady = await _ensureReadingVoice(readerLanguage);
        if (!voiceReady) return; // Voice missing: said once, not guessed.
        if (generation != _generation) return;
      }

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
      // Words came back, so a later wordless scene may once again deserve one
      // honest sentence instead of silence.
      _lastNotTextAt = null;

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
        // A readable result ends the unreadable-marks episode, so the next one
        // may speak once again.
        _lastHonestyAt = null;
        _stability.add(text);

        // Automatic reading stays silent when the result is only doubtful.
        //
        // Saying "I am not sure" again and again while the camera pans a room
        // is worse than silence: nobody asked for a reading, and the apology
        // becomes the loudest thing the app does. A deliberate read (double
        // tap or "read") still gets the honest uncertain answer with its
        // warning, because then the user is waiting for one.
        final skipDoubt = !maySpeakUnprompted(tier) && !manual;
        if (skipDoubt && kDebugMode) {
          debugPrint('live: silent automatic reading tier=${tier.name}');
        }

        if ((manual || _stability.isStable) && !skipDoubt) {
          final spoken = AudioBus.instance.speakResult(
            text,
            force: manual,
            uncertain: uncertain,
            readerLanguage: readerLanguage,
          );
          if (spoken) {
            _lastSpokenAt = DateTime.now();
            if (kDebugMode) {
              debugPrint(
                'live: speak chars=${text.length} manual=$manual tier=${tier.name}',
              );
            }
            onResult(
              AudioBus.labelReading(
                text,
                uncertain: uncertain,
                language: readerLanguage,
              ),
            );
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

  /// Wakes a side question with its answer, once.
  void _completeObjectRequest(DetectedObject? match) {
    final request = _objectOnRequest;
    _objectOnRequest = null;
    _objectOnSide = null;
    if (request != null && !request.isCompleted) request.complete(match);
  }

  /// Answers any waiting frame question with null, so a stopped camera or a
  /// mode switch never leaves a caller waiting for the full timeout.
  void _cancelQuestions() {
    final colour = _colourRequest;
    _colourRequest = null;
    if (colour != null && !colour.isCompleted) colour.complete(null);

    final object = _objectOnRequest;
    _objectOnRequest = null;
    _objectOnSide = null;
    if (object != null && !object.isCompleted) object.complete(null);
  }

  /// Decodes one frame and samples the middle half of the picture.
  ///
  /// The inset avoids the edges, where a hand or table is more likely to be.
  /// A decode failure returns null rather than a colour invented from noise.
  Future<ColourReading?> _sampleCentreColour(CameraFrame frame) async {
    final rotation = rotationDegrees(
      frame.description,
      frame.deviceOrientation,
    );
    final jpeg = await cameraFrameToJpeg(frame, rotation);
    if (jpeg.isEmpty) return null;

    Codec? codec;
    Image? image;
    try {
      codec = await instantiateImageCodec(jpeg);
      final decoded = await codec.getNextFrame();
      image = decoded.image;
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      if (data == null) return null;
      return dominantColourInBox(
        data.buffer.asUint8List(),
        image.width,
        image.height,
        const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
      );
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  /// Runs YOLO on one frame and, if useful, speaks the objects it finds.
  ///
  /// Live narration is throttled to [_objectMinGap]. Manual double-tap always
  /// answers, including with "I cannot see any object clearly".
  ///
  /// A live answer must first be confirmed by [_objectTracker] so a one-frame
  /// hallucination never reaches the user's ears.
  Future<void> _detectObjects(
    CameraFrame frame, {
    required bool manual,
    required int generation,
  }) async {
    _lastObjectAt = DateTime.now();
    final side = _objectOnSide;
    final sideQuestion = _objectOnRequest != null && side != null;

    final rotation = rotationDegrees(
      frame.description,
      frame.deviceOrientation,
    );
    final encodeWatch = Stopwatch()..start();
    final jpeg = await cameraFrameToJpeg(frame, rotation);
    if (jpeg.isEmpty) {
      if (sideQuestion) _completeObjectRequest(null);
      return;
    }

    final detectWatch = Stopwatch()..start();
    final detected = await ObjectDetectService.instance.detect(
      jpeg,
      // A side question asks about one half of the view, so a slightly larger
      // pool is needed to find an object there before the list is trimmed.
      maxObjects: sideQuestion ? 8 : (developerMode ? 15 : 3),
      lenient: manual || developerMode || sideQuestion,
    );
    if (kDebugMode) {
      debugPrint(
        'live: object timing '
        'encode=${encodeWatch.elapsedMilliseconds}ms '
        'detect=${detectWatch.elapsedMilliseconds}ms '
        'bytes=${jpeg.length} found=${detected.length}',
      );
    }
    if (generation != _generation) {
      if (sideQuestion) _completeObjectRequest(null);
      return;
    }

    final confirmed = _objectTracker.update(
      detected,
      trustImmediately: manual || developerMode,
    );
    _lastObjects = confirmed;
    detectedObjects.value = developerMode ? detected : confirmed;

    if (sideQuestion) {
      DetectedObject? match;
      for (final object in detected) {
        if (object.direction != side) continue;
        if (match == null || object.area > match.area) match = object;
      }
      _completeObjectRequest(match);
      // A direct side question gets exactly one answer. Narrating the whole
      // scene as well would talk over it and answer a question nobody asked.
      return;
    }

    final hindi = _language.isHindi;

    if (confirmed.isEmpty) {
      if (!manual) return;
      _lastObjectSignature = '';
      _lastObjectSpokenAt = DateTime.now();
      final text = noObjectsMessage(hindi: hindi);
      onResult(text);
      unawaited(
        AudioBus.instance.say(text, priority: SpeechPriority.navigation),
      );
      return;
    }

    final now = DateTime.now();
    // In developer mode or continuous cadence, narration still throttles to avoid spamming.
    final due =
        _lastObjectSpokenAt == null ||
        now.difference(_lastObjectSpokenAt!) >= _objectMinGap;
    final canNarrate =
        !AudioBus.instance.hasReading &&
        !AudioBus.instance.speaking.value &&
        !AudioBus.instance.isMuted;
    if (!manual && (!due || !canNarrate)) return;

    // Three things is already a lot to listen to; more is noise.
    final spoken = confirmed.take(3).toList(growable: false);
    final message = objectDescription(spoken, hindi: hindi);
    final signature = _objectSignature(spoken);
    final repeated =
        signature == _lastObjectSignature &&
        _lastObjectSpokenAt != null &&
        now.difference(_lastObjectSpokenAt!) < _objectRepeatGap;

    if (!manual && repeated) return;

    _lastObjectSignature = signature;
    _lastObjectSpokenAt = now;

    // Field diagnostics: a wrong colour is invisible in a release build, and
    // this line is the only record of what Cue sampled.
    debugPrint(
      'live: objects '
      '${confirmed.map((object) => object.toString()).join('; ')} '
      'manual=$manual',
    );

    onResult(message);
    unawaited(
      AudioBus.instance.say(message, priority: SpeechPriority.navigation),
    );
  }

  /// A compact fingerprint of what was described, so repeating the same scene
  /// is silenced but a moved object is not.
  String _objectSignature(List<DetectedObject> objects) {
    return objects
        .map((object) {
          final metres = object.distanceMeters;
          final band = metres == null ? '?' : (metres * 2).round().toString();
          // The colour is part of what was said, so pointing at a blue mug
          // after a red one must not be swallowed as a repeat.
          final colour = object.colour?.toString() ?? '-';
          return '${object.name}:${object.direction.index}:$band:$colour';
        })
        .join('|');
  }

  /// Makes sure the voice matches the script being read.
  ///
  /// The app's language and saved preference are not touched; this only
  /// changes the engine so Hindi text is not read with the English voice.
  Future<bool> _ensureReadingVoice(CueLanguage language) async {
    if (TtsService.instance.language == language &&
        TtsService.instance.languageAvailable) {
      return true;
    }

    final ready = await TtsService.instance.setLanguage(language);
    if (ready) {
      _voiceMissingAnnounced = false;
      return true;
    }

    if (!_voiceMissingAnnounced) {
      _voiceMissingAnnounced = true;
      unawaited(
        AudioBus.instance.say(
          language.isHindi
              ? _strings.hindiVoiceMissing
              : _strings.englishVoiceMissing,
          priority: SpeechPriority.alert,
        ),
      );
    }
    return false;
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
  /// passing shadow does not trigger it, then says it once for that episode.
  /// Repeating "I see something but cannot tell what it is" every few seconds
  /// while the user pans a room is noise, not help; the message returns only
  /// after text has been seen and lost again, or when the user asks.
  void _maybeSpeakNotText({required bool manual}) {
    if (AudioBus.instance.isMuted) return;
    final now = DateTime.now();

    if (!manual) {
      if (_notTextStreak < _notTextBeforeSpeaking) return;
      // Already said it for this stretch of wordless frames.
      if (_lastNotTextAt != null) return;
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
  /// automatic path waits for a few consecutive failures and then says it once
  /// for that episode rather than repeating an apology.
  void _maybeRefuseReading({required bool manual}) {
    if (AudioBus.instance.isMuted) return;
    final now = DateTime.now();

    if (!manual) {
      if (_untrustedStreak < _untrustedBeforeSpeaking) return;
      // Already said it for this stretch of unreadable marks.
      if (_lastHonestyAt != null) return;
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

  /// Says "hold still" only after the phone has been moving for a while.
  ///
  /// Movement itself is silent: the user may be walking. A sentence is only
  /// worth it when blurred frames are blocking the reading.
  void _noteMovement(DateTime now) {
    _movingSince ??= now;
    if (_interpretation != Interpretation.text) return;
    if (now.difference(_movingSince!) < const Duration(seconds: 2)) return;
    if (AudioBus.instance.isMuted ||
        AudioBus.instance.speaking.value ||
        AudioBus.instance.hasReading) {
      return;
    }
    final last = _lastStillCueAt;
    if (last != null && now.difference(last) < const Duration(seconds: 15)) {
      return;
    }
    _lastStillCueAt = now;
    unawaited(
      AudioBus.instance.say(
        _strings.holdStill,
        priority: SpeechPriority.navigation,
      ),
    );
  }

  /// Tells the user which way to level the phone.
  ///
  /// Only portrait-up is corrected: in landscape the roll reading belongs to
  /// the rotation, not to a mistake, and upside-down has no useful "left".
  void _maybeTiltCue(DeviceOrientation orientation, DateTime now) {
    if (orientation != DeviceOrientation.portraitUp) return;
    final instruction = tiltInstructionFor(MotionMonitor.instance.rollDegrees);
    if (instruction == null) return;
    if (AudioBus.instance.isMuted ||
        AudioBus.instance.speaking.value ||
        AudioBus.instance.hasReading) {
      return;
    }
    final last = _lastTiltCueAt;
    if (last != null && now.difference(last) < const Duration(seconds: 12)) {
      return;
    }
    _lastTiltCueAt = now;
    final text = instruction == TiltInstruction.toTheLeft
        ? _strings.tiltLeft
        : _strings.tiltRight;
    unawaited(AudioBus.instance.say(text, priority: SpeechPriority.navigation));
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

/// Fraction of the letters, marks and digits in [text] that are Devanagari.
///
/// Latin OCR on a Hindi page can return strings that still look like text —
/// isolated Latin fragments are common — while carrying almost no Latin
/// content. A high fraction means the Devanagari recogniser is the right one
/// to use even if the Latin recogniser returned something.
double _devanagariFraction(String text) {
  final meaningful = RegExp(r'[\p{L}\p{M}\p{N}]', unicode: true);
  var total = 0;
  var devanagari = 0;

  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (!meaningful.hasMatch(char)) continue;
    total++;
    if (rune >= 0x0900 && rune <= 0x097F) devanagari++;
  }

  return total == 0 ? 0.0 : devanagari / total;
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
