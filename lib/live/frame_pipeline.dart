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
import '../core/personal_items.dart';
import '../core/text_similarity.dart';
import '../core/search_target.dart';
import '../core/tts_service.dart';
import '../vision/frame_source.dart';
import '../vision/ocr_service.dart';
import '../vision/camera_frame_encoder.dart';
import '../vision/currency_service.dart';
import '../vision/detected_object.dart';
import '../vision/object_detect_service.dart';
import '../vision/object_tracker.dart';
import '../vision/object_colour.dart';
import '../vision/personal_item_vision.dart';
import '../core/object_labels.dart';
import 'aiming_coach.dart';
import 'frame_metrics.dart';
import 'item_search.dart';
import 'object_announcement_history.dart';
import 'reading_quality.dart';
import 'scene_router.dart';
import 'screen_status.dart';
import 'screen_watch.dart';
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
    this.isTorchOn,
    this.waitingForTorch,
    CueLanguage language = CueLanguage.english,
  }) : _language = language; // ignore: prefer_initializing_formals

  /// Called with the text that was actually spoken, for the sighted-helper
  /// caption on screen.
  final void Function(String text) onResult;

  /// Called when an aiming instruction is issued, for logging or the caption.
  final void Function(AimingCue cue)? onCue;
  final bool Function()? isTorchOn;
  final bool Function()? waitingForTorch;

  CueLanguage _language;

  CueLanguage get language => _language;

  CueStrings get _strings => CueStrings(_language);

  static const Duration _minFrameGap = Duration(milliseconds: 320);
  static const Duration _staleAfter = Duration(milliseconds: 1400);
  static const Duration _manualTextWindow = Duration(seconds: 3);

  /// Below this mean absolute difference the scene is treated as unchanged.
  static const double _changeThreshold = 0.004;

  final FrameSampler _sampler = FrameSampler();
  final StabilityGate _stability = StabilityGate();
  final ScreenStatusTracker _screenStatus = ScreenStatusTracker();
  ScreenWatch? _screenWatch;
  final AimingCoach _coach = AimingCoach();
  CueLanguage? _textReaderLanguage;

  DateTime _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOcr = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastSpokenAt;

  bool _busy = false;
  bool _manualRequested = false;
  int _generation = 0;

  Timer? _textReadTimeout;
  String? _textReadHint;
  int _textReadRevision = 0;

  bool get isCheckingForText => _textReadTimeout != null;

  /// The last time the pipeline tried the other script. This prevents a
  /// second OCR pass on every frame on poor lighting.
  DateTime? _lastAutoDetectAt;

  /// Tilt and steadiness hints are useful but must never nag.
  DateTime? _lastTiltCueAt;
  DateTime? _lastStillCueAt;
  DateTime? _movingSince;

  /// Set once the user (or the saved setting) has been told the chosen
  /// script's voice is missing. Silence beats repeating the same warning.
  bool _voiceMissingAnnounced = false;

  /// Gap between object-detection passes while the phone is steady.
  static const Duration _objectMinGap = Duration(milliseconds: 650);

  /// Slower cadence while the phone is moving.
  ///
  /// Object mode is a scanning mode: freezing it until the hand is still
  /// leaves the user panning into silence. Frames still run while moving, but
  /// slower and without narration, because a blurred frame is not something
  /// to describe. The mode settles and speaks as soon as the hand stops.
  static const Duration _objectMovingGap = Duration(milliseconds: 1900);

  /// How long the phone must keep moving before the described scene is
  /// forgotten.
  ///
  /// Panning is how the user searches. A new view may contain the same kind of
  /// chair at the same rough distance as the old one, and a description-key
  /// cache alone cannot tell that this is a different chair. Treating a real
  /// pan as a new scene is honest: the user moved on purpose and expects the
  /// new view to be described when they stop.
  static const Duration _objectScanResetAfter = Duration(milliseconds: 800);

  /// Minimum gap between automatic object sentences.
  ///
  /// Automatic narration only speaks objects that were not already described,
  /// so this is a floor between sentences rather than a repeat timer. Manual
  /// requests ignore it.
  static const Duration _objectNarrationGap = Duration(milliseconds: 1800);

  ManualObjectScan? _requestedLook;
  Timer? _lookTimeout;
  String? _lookFallback;

  /// Tracks objects across automatic scans.
  final ObjectTracker _objectTracker = ObjectTracker();

  /// When the object mode last analysed a frame.
  DateTime _lastObjectAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// TEMP DIAG: rate-limits the object-skip reason line.
  DateTime _lastObjectDiagAt = DateTime.fromMillisecondsSinceEpoch(0);

  final _objectAnnouncements = ObjectAnnouncementHistory();

  /// When objects were last announced. Automatic narration uses it as the
  /// minimum gap between sentences; the delta check decides whether anything
  /// new is worth saying.
  DateTime? _lastObjectSpokenAt;

  /// The most recent detections, kept so a follow-up question about a side can
  /// reuse work the camera has already done.
  List<DetectedObject> _lastObjects = const <DetectedObject>[];

  List<DetectedObject> get lastObjects => _lastObjects;

  // --- Banknote mode --------------------------------------------------------

  /// Banknote checks run a little slower than the camera because OCR is the
  /// expensive part, but fast enough for two agreeing frames in about a
  /// second. The shared recogniser stays free for text mode.
  static const Duration _banknoteMinGap = Duration(milliseconds: 450);

  /// A manual check waits this long for a confirming frame before refusing.
  static const Duration _banknoteManualTimeout = Duration(milliseconds: 2500);

  /// Minimum gap between automatic note announcements.
  static const Duration _banknoteNarrationGap = Duration(milliseconds: 2600);

  /// Consecutive agreeing frames before an automatic answer is spoken.
  static const int _banknoteConfirmations = 2;

  /// Frames without a readable note before the same value may be announced
  /// again. Long enough that an intermittently-read note does not repeat.
  static const int _banknoteForgetAfter = 6;

  DateTime _lastBanknoteAt = DateTime.fromMillisecondsSinceEpoch(0);
  int? _banknoteStreakValue;
  int _banknoteStreakCount = 0;
  BanknoteEvidence _banknoteStreakEvidence = BanknoteEvidence.none;
  int _banknoteEmptyStreak = 0;
  int _banknoteMisses = 0;
  int? _announcedBanknote;
  DateTime? _lastBanknoteSpokenAt;

  /// Every candidate seen during a manual window, so a timeout can still say
  /// the value it saw most often instead of a flat refusal.
  final Map<int, int> _banknoteManualSeen = <int, int>{};
  int? _banknoteManualLast;

  /// A double tap asks for an answer even when one frame is not enough.
  bool _banknoteManualPending = false;
  DateTime? _banknoteManualDeadline;

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

  /// What the user last told Cue to look for.
  bool automaticDescriptions = false;

  Interpretation _interpretation = Interpretation.text;

  Interpretation get interpretation => _interpretation;

  /// Switches interpretation and lets the next frame be analysed immediately.
  ///
  /// Called by the side-swipe gesture. The caller is responsible for telling
  /// the user which mode was chosen; this method only changes state.
  void setInterpretation(Interpretation value) {
    if (value == _interpretation) return;
    reset();
    _interpretation = value;
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
    if (_screenWatch case final watch?) _observeScreenWatch(watch, frame);
    unawaited(_handle(frame));
  }

  bool get isWatchingScreen => _screenWatch != null;

  void startScreenWatch() {
    reset();
    _interpretation = Interpretation.text;
    _screenWatch = ScreenWatch();
  }

  bool stopScreenWatch() {
    if (_screenWatch == null) return false;
    cancelRequestedScans();
    _screenWatch = null;
    _screenStatus.reset();
    _textReaderLanguage = null;
    _generation++;
    return true;
  }

  void _observeScreenWatch(ScreenWatch watch, CameraFrame frame) {
    final audio = AudioBus.instance;
    final notice = watch.observe(
      frame,
      DateTime.now(),
      phoneMoving: MotionMonitor.instance.isMoving || audio.isMuted,
      canAnnounce:
          !audio.isSpeaking && !isCheckingForText && _requestedLook == null,
    );
    if (notice == null ||
        (notice == ScreenWatchNotice.movement && _screenStatus.hasCandidate)) {
      return;
    }
    final message = switch (notice) {
      ScreenWatchNotice.movement => _strings.screenMovement,
      ScreenWatchNotice.unchanged => _strings.screenUnchanged(
        ScreenWatch.unchangedAfter.inSeconds,
      ),
      ScreenWatchNotice.unclear => _strings.screenUnclear,
    };
    unawaited(_speakScreenReading(message, _generation));
  }

  ItemSearch? _itemSearch;
  Timer? _searchDeadline;
  final _personalVision = const PersonalItemVision();

  bool get isSearchingForItem => _itemSearch != null;

  String? get activeItemName {
    final search = _itemSearch;
    final builtIn = search?.target;
    return builtIn == null
        ? search?.personalItem?.name
        : _language.isHindi
        ? builtIn.hindi
        : builtIn.english;
  }

  void startItemSearch(SearchTarget target) => _startItemSearch(
    ItemSearch(target, DateTime.now()),
    _strings.itemNotSeen(target),
  );

  void startPersonalItemSearch(PersonalItem item) => _startItemSearch(
    ItemSearch.personal(item, DateTime.now()),
    _strings.namedItemNotSeen(item.name),
  );

  void _startItemSearch(ItemSearch search, String timeoutMessage) {
    reset();
    _interpretation = Interpretation.object;
    _itemSearch = search;
    _searchDeadline = Timer(const Duration(seconds: 30), () {
      _finishItemSearch(search, timeoutMessage);
    });
  }

  bool stopItemSearch() {
    if (_itemSearch == null) return false;
    _itemSearch = null;
    _searchDeadline?.cancel();
    _searchDeadline = null;
    detectedObjects.value = const [];
    return true;
  }

  Future<void> _searchFrame(
    CameraFrame frame,
    ItemSearch search,
    DateTime capturedAt,
  ) async {
    // A small item on a plain surface can be sharp even when the scene-wide
    // blur score is low. Let the model and the fresh-frame tracker check it.
    final rotation = rotationDegrees(
      frame.description,
      frame.deviceOrientation,
    );
    search.beginFrame(capturedAt, rotation);
    final jpeg = await cameraFrameToJpeg(
      frame,
      rotation,
      region: search.region,
    );
    if (!identical(search, _itemSearch)) return;
    final personal = search.personalItem;
    final List<DetectedObject> candidates;
    ObjectDirection? personalDirection;
    if (personal == null) {
      candidates = await ObjectDetectService.everyday.detect(
        jpeg,
        searchTarget: search.target,
      );
    } else {
      final observation = await _personalVision.find(
        jpeg,
        uprightSize(frame.image.width, frame.image.height, rotation),
        personal,
        detail: search.scanDetail,
        verifyCrop: search.isVerifying,
      );
      candidates = observation.candidates;
      personalDirection = observation.direction;
    }
    if (!identical(search, _itemSearch) || AudioBus.instance.isMuted) return;
    final now = DateTime.now();
    if (now.difference(capturedAt) > _staleAfter &&
        MotionMonitor.instance.isMoving) {
      return;
    }
    final observation = search.observe(
      candidates,
      personalDirection: personalDirection,
    );
    if (developerMode) detectedObjects.value = observation.candidates;
    final match = observation.match;
    if (match == null) {
      if (AudioBus.instance.speaking.value) return;
      final hasCandidate = observation.candidates.isNotEmpty;
      final shouldCue = hasCandidate
          ? search.takeCandidateHint()
          : search.takeHint(now);
      if (!shouldCue) return;
      final message = hasCandidate
          ? _strings.itemCandidateHint
          : _strings.itemSearchHint;
      onResult(message);
      unawaited(
        AudioBus.instance.say(message, priority: SpeechPriority.navigation),
      );
      return;
    }
    final answer = personal == null
        ? objectDescription(
            [match],
            hindi: _language.isHindi,
            includeDistance: false,
          )
        : _strings.personalItemFound(
            personal.name,
            observation.personalDirection,
          );
    _finishItemSearch(search, answer, match: match);
  }

  void _finishItemSearch(
    ItemSearch search,
    String message, {
    DetectedObject? match,
  }) {
    if (!identical(search, _itemSearch)) return;
    stopItemSearch();
    if (match != null) {
      detectedObjects.value = [match];
      unawaited(Feedback.instance.itemFound());
    }
    onResult(message);
    unawaited(AudioBus.instance.say(message, priority: SpeechPriority.answer));
  }

  /// Starts a check from a double tap or voice command.
  bool requestManualRead({bool wholeScene = false}) {
    if (_interpretation == Interpretation.object) {
      return _requestObjectScan(
        wholeScene ? ObjectScanType.scene : ObjectScanType.item,
      );
    }
    stopItemSearch();
    _endLook();
    if (_interpretation == Interpretation.text) {
      if (isCheckingForText) return false;
      _textReadRevision++;
      _stability.reset();
      _lastAutoDetectAt = null;
      _textReadTimeout = Timer(_manualTextWindow, () {
        final hint = _textReadHint ?? _strings.aimAtText;
        cancelTextRead();
        if (AudioBus.instance.isMuted) return;
        final now = DateTime.now();
        _lastSpokenAt = now;
        _lastStillCueAt = now;
        _lastTiltCueAt = now;
        unawaited(AudioBus.instance.say(hint, priority: SpeechPriority.answer));
        onResult(hint);
      });
    } else {
      _manualRequested = true;
    }
    return true;
  }

  bool requestObjectDetails() =>
      _requestObjectScan(ObjectScanType.itemWithText);

  bool _requestObjectScan(ObjectScanType type) {
    if (_requestedLook != null) return false;
    stopItemSearch();
    cancelTextRead();
    final look = ManualObjectScan(type: type);
    _requestedLook = look;
    _lookTimeout = Timer(const Duration(seconds: 4), () {
      final fallback =
          _lookFallback ?? (look.focused ? _strings.aimAtItem : null);
      _endLook();
      _answerObjectScan(fallback);
    });
    return true;
  }

  /// Cancels pending Text and Object requests when the user interrupts.
  void cancelRequestedScans() {
    cancelTextRead();
    _endLook();
  }

  void cancelTextRead() {
    final timeout = _textReadTimeout;
    if (timeout == null) return;
    timeout.cancel();
    _textReadTimeout = null;
    _textReadHint = null;
    _textReadRevision++;
    _stability.reset();
  }

  void _endLook() {
    _lookTimeout?.cancel();
    _lookTimeout = null;
    _requestedLook = null;
    _lookFallback = null;
  }

  void _answerObjectScan([String? answer]) {
    if (AudioBus.instance.isMuted) return;
    final text = answer ?? noObjectsMessage(hindi: _language.isHindi);
    _lastObjectSpokenAt = DateTime.now();
    onResult(text);
    unawaited(AudioBus.instance.say(text, priority: SpeechPriority.navigation));
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
  /// A running frame still owns the analyser until its native call returns.
  void reset() {
    stopItemSearch();
    _generation++;
    cancelRequestedScans();
    detectedObjects.value = const <DetectedObject>[];
    _sampler.reset();
    _stability.reset();
    _screenStatus.reset();
    _screenWatch = null;
    _textReaderLanguage = null;
    _coach.reset();
    _manualRequested = false;
    _lastTiltCueAt = null;
    _lastStillCueAt = null;
    _movingSince = null;
    _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastOcr = DateTime.fromMillisecondsSinceEpoch(0);
    _lastSpokenAt = null;
    _lastAutoDetectAt = null;
    _lastObjectAt = DateTime.fromMillisecondsSinceEpoch(0);
    _objectAnnouncements.reset();
    _lastObjectSpokenAt = null;
    _lastObjects = const <DetectedObject>[];
    _objectTracker.reset();
    _resetBanknote();
    _cancelQuestions();
  }

  /// Forgets every frame-to-frame note decision.
  ///
  /// Called when the mode changes and when the camera restarts, so a note seen
  /// before a pause cannot be announced as if it were still in view.
  void _resetBanknote() {
    _lastBanknoteAt = DateTime.fromMillisecondsSinceEpoch(0);
    _banknoteStreakValue = null;
    _banknoteStreakCount = 0;
    _banknoteStreakEvidence = BanknoteEvidence.none;
    _banknoteEmptyStreak = 0;
    _banknoteMisses = 0;
    _announcedBanknote = null;
    _lastBanknoteSpokenAt = null;
    _banknoteManualSeen.clear();
    _banknoteManualLast = null;
    _banknoteManualPending = false;
    _banknoteManualDeadline = null;
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
        _busy = false;
      }
      return;
    }

    final search = _itemSearch;
    if (search != null && _objectOnRequest == null) {
      if (AudioBus.instance.isMuted || !search.ready(now)) return;
      _busy = true;
      try {
        await _searchFrame(frame, search, now);
      } catch (error) {
        if (kDebugMode) debugPrint('Item search frame failed: $error');
        _finishItemSearch(search, _strings.itemSearchUnavailable);
      } finally {
        _busy = false;
      }
      return;
    }

    // A moving phone produces blurred frames. Text reading waits for the hand
    // to settle; object mode keeps scanning, because panning is how a blind
    // user searches for something. Banknote mode also waits for a steady
    // frame: blurred numerals are exactly what makes a note misread.
    final quietObject =
        _interpretation == Interpretation.object && !automaticDescriptions;
    if (quietObject &&
        !developerMode &&
        _requestedLook == null &&
        !_manualRequested &&
        _objectOnRequest == null) {
      return;
    }
    final moving = MotionMonitor.instance.isMoving;
    if (moving &&
        _requestedLook == null &&
        !_manualRequested &&
        !isCheckingForText &&
        !_banknoteManualPending &&
        _objectOnRequest == null) {
      // A long scan gets one "hold still" hint. A direct request does not:
      // the user is already waiting for an answer.
      if (!quietObject && !isWatchingScreen) _noteMovement(now);
      if (_interpretation != Interpretation.object &&
          _interpretation != Interpretation.banknote) {
        return;
      }
    } else if (!moving) {
      _movingSince = null;
    }

    // Object mode: the camera feeds YOLO instead of the text recogniser.
    if (_interpretation == Interpretation.object ||
        _requestedLook != null ||
        _objectOnRequest != null) {
      final sideQuestion = _objectOnRequest != null;
      final look = sideQuestion ? null : _requestedLook;
      if (look != null && !look.ready(now)) return;
      final manual = look != null || sideQuestion;
      _manualRequested = false;

      // A sustained pan is a new view. Forget what the old view said so the
      // new one is described when the hand stops, even if it happens to
      // contain the same kind of object at the same distance.
      if (!manual &&
          moving &&
          _movingSince != null &&
          now.difference(_movingSince!) >= _objectScanResetAfter) {
        _objectAnnouncements.reset();
      }

      final canNarrate =
          !AudioBus.instance.hasReading &&
          !AudioBus.instance.speaking.value &&
          !AudioBus.instance.isMuted;
      final due =
          now.difference(_lastObjectAt) >=
          (moving ? _objectMovingGap : _objectMinGap);
      final devDue =
          developerMode &&
          now.difference(_lastObjectAt) >= const Duration(milliseconds: 250);

      // Detection stays warm while a sentence is being spoken: the tracker
      // can confirm the next object during playback, so scanning does not go
      // blind for the length of every description. Muting is different; there
      // is no answer to prepare, so the work is skipped.
      if (!manual && !devDue && (!due || AudioBus.instance.isMuted)) {
        if (kDebugMode &&
            now.difference(_lastObjectDiagAt) > const Duration(seconds: 3)) {
          _lastObjectDiagAt = now;
          debugPrint(
            'live: object skip due=$due narrate=$canNarrate '
            'muted=${AudioBus.instance.isMuted} '
            'speaking=${AudioBus.instance.speaking.value} '
            'reading=${AudioBus.instance.hasReading} '
            'moving=$moving',
          );
        }
        return;
      }

      _busy = true;
      try {
        await _detectObjects(
          frame,
          manual: manual,
          generation: generation,
          look: look,
          capturedAt: now,
        );
      } catch (error) {
        if (kDebugMode) debugPrint('Object scan failed: $error');
        if (generation != _generation) return;
        if (sideQuestion) {
          _completeObjectRequest(null);
        } else if (look != null && identical(_requestedLook, look)) {
          final fallback = _lookFallback ?? _strings.objectScanUnavailable;
          _endLook();
          _answerObjectScan(fallback);
        }
      } finally {
        _busy = false;
      }
      return;
    }

    // Banknote mode: the printed denomination is read by OCR, not by a
    // classifier. A steady frame is required because motion blur turns an 8
    // into a 3, and a wrong amount is an expensive thing to say confidently.
    if (_interpretation == Interpretation.banknote) {
      var manual = _manualRequested || _banknoteManualPending;
      _manualRequested = false;

      if (_banknoteManualPending) {
        final deadline = _banknoteManualDeadline;
        if (deadline != null && now.isAfter(deadline)) {
          _banknoteManualPending = false;
          _banknoteManualDeadline = null;
          final seen = _banknoteManualChoice();
          _banknoteManualSeen.clear();
          _banknoteManualLast = null;
          if (seen != null) {
            _speakBanknoteUncertain(seen);
          } else {
            _speakBanknoteProblem(BanknoteProblem.unclear);
          }
          return;
        }
      } else if (manual) {
        // Keep trying for a short window instead of answering from one frame
        // that may not have been enough.
        _banknoteManualPending = true;
        _banknoteManualDeadline = now.add(_banknoteManualTimeout);
      }

      if (!manual && now.difference(_lastBanknoteAt) < _banknoteMinGap) {
        return;
      }

      _busy = true;
      try {
        await _readBanknote(frame, manual: manual, generation: generation);
      } finally {
        _busy = false;
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
    final revision = _textReadRevision;
    final manual = isCheckingForText;
    final watchingScreen = isWatchingScreen;

    // A frame belongs to the check (or automatic scan) that started it.
    bool isCurrentRead() =>
        generation == _generation &&
        revision == _textReadRevision &&
        _requestedLook == null;

    if (manual) {
      _textReadHint = metrics.isTooDark
          ? _strings.lightForText
          : moving || metrics.isTooBlurry
          ? _strings.steadyForText
          : _strings.aimAtText;
    }

    // Follow small progress numbers even when the frame looks unchanged.
    final readInterval = _screenStatus.hasCandidate
        ? const Duration(milliseconds: 700)
        : _staleAfter;
    // A stale scene is analysed periodically even if the change
    // gate says nothing moved. Without this, a perfectly still page would
    // never be read, and a permanently soft camera would look dead.
    final stale = now.difference(_lastOcr) > readInterval;
    final tooBlurry = metrics.isTooBlurry;
    final unchanged = metrics.change < _changeThreshold;

    if (!manual && !stale && (tooBlurry || unchanged)) {
      if (tooBlurry && !metrics.isTooDark && !watchingScreen) {
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
      // Keep the recogniser that found the current text for the next frame.
      CueLanguage readerLanguage = _textReaderLanguage ?? _language;
      final bytes = frame.nv21;
      OcrRead read = await OcrService.instance.readLiveFrame(
        nv21: bytes,
        width: frame.image.width,
        height: frame.image.height,
        rotation: rotation,
        bytesPerRow: frame.bytesPerRow,
        language: readerLanguage,
      );

      // A stop/resume while OCR was queued cancels everything that follows,
      // including the language-switch choice below.
      if (!isCurrentRead()) return;
      var status = analyseScreenStatus(
        read.text,
        includeInputPrompts: watchingScreen,
      );

      // Script auto-detection: if the selected recogniser returned nothing
      // useful, try the other script. The app decides this by itself because
      // a blind user cannot see that they are holding the other script.
      final speaking = AudioBus.instance.speaking.value;
      final lastAuto = _lastAutoDetectAt;
      final scriptRetryGap = manual
          ? const Duration(milliseconds: 900)
          : const Duration(seconds: 15);
      final autoDetectAllowed =
          (lastAuto == null || now.difference(lastAuto) > scriptRetryGap) &&
          (manual || (!speaking && !AudioBus.instance.hasReading));

      var text = speakable(read.text);
      var quality = ReadingQuality.of(text, read.confidence);
      final selectedTier = quality.tier;
      final mostlyDevanagari = _devanagariFraction(read.text) > 0.15;
      final scriptMismatch = readerLanguage.isHindi
          ? !mostlyDevanagari
          : mostlyDevanagari || !looksLikeEnglishText(text);
      final tryOther =
          status == null &&
          (selectedTier != ReadingTier.certain || scriptMismatch) &&
          !metrics.isTooBlurry &&
          autoDetectAllowed;

      if (tryOther) {
        _lastAutoDetectAt = now;
        final other = readerLanguage == CueLanguage.english
            ? CueLanguage.hindi
            : CueLanguage.english;
        final otherRead = await OcrService.instance.readLiveFrame(
          nv21: bytes,
          width: frame.image.width,
          height: frame.image.height,
          rotation: rotation,
          bytesPerRow: frame.bytesPerRow,
          language: other,
        );

        if (!isCurrentRead()) return;
        final otherStatus = analyseScreenStatus(
          otherRead.text,
          includeInputPrompts: watchingScreen,
        );
        final otherText = speakable(otherRead.text);
        final otherQuality = ReadingQuality.of(otherText, otherRead.confidence);
        final otherTier = otherQuality.tier;
        final otherIsDevanagari = _devanagariFraction(otherText) > 0.15;
        final otherMatchesScript = other.isHindi
            ? otherIsDevanagari
            : !otherIsDevanagari && looksLikeEnglishText(otherText);
        if (!manual && otherStatus != null) {
          readerLanguage = other;
          read = otherRead;
          text = otherText;
          quality = otherQuality;
          status = otherStatus;
        } else if (otherTier != ReadingTier.refused &&
            (otherTier.index < selectedTier.index ||
                (otherTier == selectedTier &&
                    scriptMismatch &&
                    otherMatchesScript))) {
          final previousVoice = TtsService.instance.language;
          if (await _ensureReadingVoice(other)) {
            if (!isCurrentRead()) return;
            if (kDebugMode) {
              debugPrint('live: auto-detected ${other.label} script');
            }
            if (!manual && previousVoice != other) {
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
            text = otherText;
            quality = otherQuality;
            status = otherStatus;
          }
        }
      }
      // The switch itself is awaited, so the camera may have stopped while we
      // waited for the voice. Do not speak from a superseded session.
      if (!isCurrentRead()) return;

      final confidence = read.confidence;
      final candidate = confidence == null || confidence >= minTrustedConfidence
          ? status
          : null;
      _textReaderLanguage = status != null || quality.speakable
          ? readerLanguage
          : null;
      final update = _screenStatus.observe(candidate, now);
      if (!manual && status != null) {
        _stability.reset();
        if (update != null) await _announceScreenStatus(update, generation);
        return;
      }

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

      if (!quality.speakable) {
        _stability.reset();
        return;
      }

      final stable = _stability.add(text);
      final certain = maySpeakUnprompted(quality.tier);
      // A clear manual result is immediate. Doubtful text needs a second
      // matching frame and is only spoken in response to an explicit check.
      final shouldRead = manual ? certain || stable : certain && stable;
      if (shouldRead) {
        if (!await _ensureReadingVoice(readerLanguage) || !isCurrentRead()) {
          return;
        }
        final audio = AudioBus.instance;
        final spoken = audio.speakResult(
          text,
          force: manual,
          uncertain: !certain,
          readerLanguage: readerLanguage,
        );
        if (spoken) {
          if (manual) cancelTextRead();
          _lastSpokenAt = DateTime.now();
          if (candidate != null) {
            _screenStatus.markAnnounced(candidate, _lastSpokenAt!);
          }
          onResult(
            AudioBus.labelReading(
              text,
              uncertain: !certain,
              language: readerLanguage,
            ),
          );
          if (certain) unawaited(Feedback.instance.found());
          return;
        }
      }

      // Idle Text mode only coaches framing when there is a text layout.
      if (manual || watchingScreen || read.blocks.isEmpty) return;

      final frameSize = rotatedSize(
        frame.image.width,
        frame.image.height,
        rotation,
      );
      final layout = TextLayout.fromRects(
        read.blocks.map((block) => block.boundingBox).toList(growable: false),
        frameSize,
        wordCount: _wordCount(text),
      );

      if (kDebugMode) {
        debugPrint(
          'live: aim centerX=${layout.centerX.toStringAsFixed(2)} '
          'coverage=${layout.coverage.toStringAsFixed(3)} '
          'height=${layout.heightRatio.toStringAsFixed(2)} '
          'words=${layout.wordCount} rotation=$rotation '
          'frame=${frameSize.width.toInt()}x${frameSize.height.toInt()}',
        );
      }

      _maybeAim(metrics, layout, DateTime.now(), text);
    } catch (_) {
      // One bad frame must never take the live screen down. The next frame
      // gets another chance.
    } finally {
      _busy = false;
    }
  }

  Future<void> _announceScreenStatus(
    ScreenStatus status,
    int generation,
  ) async {
    final message = screenStatusSpeech(status, hindi: _language.isHindi);
    if (await _speakScreenReading(message, generation)) {
      _screenStatus.markAnnounced(status, _lastSpokenAt!);
    }
  }

  Future<bool> _speakScreenReading(String message, int generation) async {
    final audio = AudioBus.instance;
    if (audio.isMuted ||
        audio.isSpeaking ||
        isCheckingForText ||
        _requestedLook != null) {
      return false;
    }
    final language = _language;
    if (!await _ensureReadingVoice(language) || generation != _generation) {
      return false;
    }
    if (audio.isSpeaking || isCheckingForText || _requestedLook != null) {
      return false;
    }

    // Text deduplication would otherwise treat a new percentage as one
    // changed word in the same sentence.
    if (!audio.speakResult(message, force: true, readerLanguage: language)) {
      return false;
    }
    _lastSpokenAt = DateTime.now();
    onResult(message);
    return true;
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
  /// Automatic narration is paced by [_objectNarrationGap] and speaks only
  /// objects that were not already described. Manual double-tap always
  /// answers or gives a framing hint.
  ///
  /// A live answer must first be confirmed by [_objectTracker] so a one-frame
  /// hallucination never reaches the user's ears.
  Future<void> _detectObjects(
    CameraFrame frame, {
    required bool manual,
    required int generation,
    required ManualObjectScan? look,
    required DateTime capturedAt,
  }) async {
    _lastObjectAt = DateTime.now();
    final side = _objectOnSide;
    final sideQuestion = _objectOnRequest != null && side != null;
    String? qualityHint;

    if (!sideQuestion) {
      final quality = _sampler.sample(frame.image);
      // Keep the original request pending while automatic lighting settles.
      if (quality.isTooDark && (waitingForTorch?.call() ?? false)) return;
      final torchOn = isTorchOn?.call() ?? false;
      final tooDark = quality.isTooDark && torchOn;
      if (tooDark || quality.isTooBlurry) {
        // A small, sharp item on a plain surface can score low for the whole
        // frame. While steady, let the detector check any frame with detail.
        if (look == null &&
            (tooDark ||
                quality.sharpness <= 0 ||
                MotionMonitor.instance.isMoving)) {
          detectedObjects.value = const [];
          _lastObjects = const [];
          _objectTracker.reset();
          return;
        }
        if (look != null) {
          qualityHint = quality.isTooDark
              ? _strings.objectTooDark(torchOn: torchOn)
              : _strings.objectTooBlurry;
        }
      }
    }

    final rotation = rotationDegrees(
      frame.description,
      frame.deviceOrientation,
    );
    final region = look?.region;
    final encodeWatch = Stopwatch()..start();
    final jpeg = await cameraFrameToJpeg(frame, rotation, region: region);
    if (generation != _generation ||
        (look != null && !identical(_requestedLook, look))) {
      return;
    }

    final detectWatch = Stopwatch()..start();
    final detector = manual
        ? ObjectDetectService.instance
        : ObjectDetectService.everyday;
    final detected = await detector.detect(
      jpeg,
      maxObjects: sideQuestion ? 8 : (look == null && developerMode ? 15 : 5),
      includeCandidates: look == null && (developerMode || sideQuestion),
      includePeople: look?.focused != true,
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
      return;
    }

    if (look != null && !identical(_requestedLook, look)) return;
    if (look == null && !sideQuestion && _requestedLook != null) return;
    final List<DetectedObject> confirmed;
    if (look != null) {
      final result = look.observe(capturedAt, detected);
      if (result == null) return;
      confirmed = result;
      if (!look.focused) _endLook();
    } else {
      final candidates = developerMode || sideQuestion
          ? detected.where(isConfidentDetection).toList()
          : detected;
      confirmed = _objectTracker.update(candidates);
    }
    _lastObjects = confirmed;
    detectedObjects.value = developerMode && region == null
        ? detected
        : confirmed;

    final hindi = _language.isHindi;
    if (look != null && look.focused && region != null) {
      final subject = confirmed.singleOrNull;
      final description = objectDescription(
        confirmed,
        hindi: hindi,
        includeDistance: false,
      );
      // Keep the confirmed description available if OCR outlasts the scan.
      final fallback = description.isEmpty
          ? (qualityHint ?? _strings.aimAtItem)
          : description;
      _lookFallback = fallback;
      final text = look.type == ObjectScanType.itemWithText
          ? await _readObjectText(frame, rotation, subject?.box ?? region)
          : '';
      if (!identical(_requestedLook, look)) return;
      _endLook();
      if (description.isNotEmpty) {
        _objectAnnouncements.remember(confirmed, DateTime.now());
      }
      _answerObjectScan(
        text.isEmpty
            ? fallback
            : '$description ${_strings.visibleObjectText(text)}'.trim(),
      );
      return;
    }

    if (sideQuestion) {
      DetectedObject? match;
      for (final object in detected) {
        if (object.direction != side || !isConfidentDetection(object)) {
          continue;
        }
        if (match == null || object.area > match.area) match = object;
      }
      _completeObjectRequest(match);
      // A direct side question gets exactly one answer. Narrating the whole
      // scene as well would talk over it and answer a question nobody asked.
      return;
    }

    if (confirmed.isEmpty) {
      if (!manual) return;
      _answerObjectScan(qualityHint);
      return;
    }

    final now = DateTime.now();
    final settled = !MotionMonitor.instance.isMoving;

    // Describe the whole group when a new instance appears in it.
    final describable = confirmed.take(5).toList(growable: false);
    final identityOf = look == null ? _objectTracker.identityOf : null;
    final alreadySpoken = _objectAnnouncements.observe(
      describable,
      now,
      identityOf: identityOf,
    );
    final groups = <(String, ObjectDirection), List<DetectedObject>>{};
    for (final object in describable) {
      groups
          .putIfAbsent((
            object.label,
            object.direction,
          ), () => <DetectedObject>[])
          .add(object);
    }
    final newGroups = groups.values
        .where(
          (group) => group.any((object) => !alreadySpoken.contains(object)),
        )
        .toList(growable: false);

    final due =
        _lastObjectSpokenAt == null ||
        now.difference(_lastObjectSpokenAt!) >= _objectNarrationGap;
    final canNarrate =
        !AudioBus.instance.hasReading &&
        !AudioBus.instance.speaking.value &&
        !AudioBus.instance.isMuted;
    if (!manual &&
        (!automaticDescriptions || !due || !canNarrate || !settled)) {
      return;
    }

    // Describe up to three groups per answer and keep each group's count.
    final selected = manual ? groups.values : newGroups;
    final spoken = selected.take(3).expand((group) => group).toList();
    if (spoken.isEmpty) return;

    final message = objectDescription(
      spoken,
      hindi: hindi,
      includeDistance: false,
    );
    if (message.isEmpty) {
      // Hindi is frozen, so an object whose name was too close to call has no
      // Hindi sentence. Silence is right for automatic narration; a manual
      // request still gets the existing "unrecognised object" line.
      if (manual) {
        _lastObjectSpokenAt = now;
        final fallback = _strings.somethingThere;
        onResult(fallback);
        unawaited(
          AudioBus.instance.say(fallback, priority: SpeechPriority.navigation),
        );
      }
      return;
    }

    _lastObjectSpokenAt = now;
    _objectAnnouncements.remember(spoken, now, identityOf: identityOf);

    // Field diagnostics: a wrong colour is invisible in a release build, and
    // this line is the only record of what Cue sampled.
    debugPrint(
      'live: objects '
      '${confirmed.map((object) => object.toString()).join('; ')} '
      'manual=$manual newGroups=${newGroups.length}',
    );

    onResult(message);
    unawaited(
      AudioBus.instance.say(message, priority: SpeechPriority.navigation),
    );
  }

  /// Reads a small amount of clear text from the same frame as the close-up.
  Future<String> _readObjectText(
    CameraFrame frame,
    int rotation,
    Rect region,
  ) async {
    final width = frame.image.width;
    final height = frame.image.height;
    final read = await OcrService.instance.readLiveFrame(
      nv21: frame.nv21,
      width: width,
      height: height,
      rotation: rotation,
      bytesPerRow: frame.bytesPerRow,
      language: _language,
    );
    final size = rotatedSize(width, height, rotation);
    final bounds = Rect.fromLTRB(
      region.left * size.width,
      region.top * size.height,
      region.right * size.width,
      region.bottom * size.height,
    );
    final lines = <String>{};
    for (final block in read.blocks) {
      for (final line in block.lines) {
        final box = line.boundingBox;
        final overlap = box.intersect(bounds);
        if (overlap.isEmpty ||
            overlap.width * overlap.height < box.width * box.height * 0.8) {
          continue;
        }
        final text = speakable(line.text);
        if (text.length > 80 ||
            ReadingQuality.of(text, line.confidence).tier !=
                ReadingTier.certain) {
          continue;
        }
        lines.add(text);
        if (lines.length == 2) return lines.join(', ');
      }
    }
    return lines.join(', ');
  }

  /// Reads one banknote frame and answers when the evidence is sufficient.
  ///
  /// Automatic answers need two agreeing frames. A manual double tap answers
  /// as soon as one frame repeats the value or sees the RBI banner. A close-up
  /// that shows only one numeral is spoken with an explicit hedge rather than
  /// stated as fact, because "₹200" for a ₹2000 note costs real money.
  Future<void> _readBanknote(
    CameraFrame frame, {
    required bool manual,
    required int generation,
  }) async {
    _lastBanknoteAt = DateTime.now();

    final rotation = rotationDegrees(
      frame.description,
      frame.deviceOrientation,
    );
    final read = await OcrService.instance.readLiveFrame(
      nv21: frame.nv21,
      width: frame.image.width,
      height: frame.image.height,
      rotation: rotation,
      bytesPerRow: frame.bytesPerRow,
      // The denomination numerals and the RBI banner are Latin script, so a
      // note reads the same whichever language the app is set to.
      language: CueLanguage.english,
    );
    if (generation != _generation) return;

    final reading = analyseBanknoteText(read.text);
    if (kDebugMode) {
      final preview = read.text.replaceAll('\n', ' ').trim();
      debugPrint(
        'live: banknote $reading chars=${read.text.length} manual=$manual '
        'text=${preview.length > 120 ? preview.substring(0, 120) : preview}',
      );
    }

    final value = reading.rupees;
    if (value == null) {
      _noteBanknoteMiss();
      // A manual request is not refused on one empty frame. OCR misses a note
      // at an angle or in a shadow; the timeout decides when to give up.
      return;
    }

    if (manual) {
      _banknoteManualSeen.update(
        value,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      _banknoteManualLast = value;
    }

    if (_banknoteStreakValue == value) {
      _banknoteStreakCount++;
      if (reading.evidence.index > _banknoteStreakEvidence.index) {
        _banknoteStreakEvidence = reading.evidence;
      }
    } else {
      _banknoteStreakValue = value;
      _banknoteStreakCount = 1;
      _banknoteStreakEvidence = reading.evidence;
    }
    _banknoteEmptyStreak = 0;
    _banknoteMisses = 0;

    // A manual check answers as soon as one frame repeats the value or sees
    // the banner, which is what makes a close-up usable in under a second.
    // Automatic narration always wants two frames.
    final corroborated =
        reading.evidence.index >= BanknoteEvidence.medium.index;
    final confirmed =
        _banknoteStreakCount >= _banknoteConfirmations ||
        (manual && corroborated);
    if (!confirmed) return;

    final now = DateTime.now();
    if (!manual) {
      final canNarrate =
          !AudioBus.instance.hasReading &&
          !AudioBus.instance.speaking.value &&
          !AudioBus.instance.isMuted &&
          !MotionMonitor.instance.isMoving;
      final due =
          _lastBanknoteSpokenAt == null ||
          now.difference(_lastBanknoteSpokenAt!) >= _banknoteNarrationGap;
      // Holding the same note still must not repeat the amount every few
      // seconds. A different value is new information and is spoken.
      if (!canNarrate || !due || _announcedBanknote == value) return;
    }

    final uncertain = _banknoteStreakEvidence == BanknoteEvidence.weak;

    _announcedBanknote = value;
    _lastBanknoteSpokenAt = now;
    _banknoteManualPending = false;
    _banknoteManualDeadline = null;
    _banknoteManualSeen.clear();
    _banknoteManualLast = null;

    final text = uncertain
        ? _strings.banknoteUncertain(value)
        : _strings.banknoteAnswer(value);
    onResult(text);
    unawaited(
      AudioBus.instance.say(
        text,
        priority: manual ? SpeechPriority.answer : SpeechPriority.navigation,
      ),
    );
  }

  /// Counts a frame with no denomination.
  ///
  /// One empty frame between two readings is normal OCR jitter, so the
  /// agreeing-value streak survives it. The last announcement is only
  /// forgotten after the note has been out of view for a while, which is what
  /// lets the user put a note down and show the same value again later.
  void _noteBanknoteMiss() {
    _banknoteEmptyStreak++;
    _banknoteMisses++;
    if (_banknoteEmptyStreak >= 2) {
      _banknoteStreakValue = null;
      _banknoteStreakCount = 0;
    }
    if (_banknoteMisses >= _banknoteForgetAfter) {
      _announcedBanknote = null;
    }
  }

  /// The value seen most often in a manual window, or null.
  int? _banknoteManualChoice() {
    if (_banknoteManualSeen.isEmpty) return null;

    int? best;
    var bestCount = 0;
    for (final entry in _banknoteManualSeen.entries) {
      if (entry.value > bestCount) {
        best = entry.key;
        bestCount = entry.value;
      }
    }

    // A tie goes to the most recent candidate: that is the one in view now.
    final last = _banknoteManualLast;
    if (best != null &&
        last != null &&
        _banknoteManualSeen[last] == bestCount) {
      return last;
    }
    return best;
  }

  /// Speaks a value Cue saw but could not corroborate.
  ///
  /// The sentence is hedged in English. Hindi is frozen, so it falls back to
  /// the existing "unrecognised" line rather than asserting a maybe as fact.
  void _speakBanknoteUncertain(int value) {
    if (AudioBus.instance.isMuted) return;
    _lastBanknoteSpokenAt = DateTime.now();
    _announcedBanknote = value;
    final text = _strings.banknoteUncertain(value);
    onResult(text);
    unawaited(AudioBus.instance.say(text, priority: SpeechPriority.answer));
  }

  /// Answers a manual check that did not produce a value.
  void _speakBanknoteProblem(BanknoteProblem problem) {
    if (AudioBus.instance.isMuted) return;
    _lastBanknoteSpokenAt = DateTime.now();
    final text = problem == BanknoteProblem.mixedNotes
        ? _strings.banknoteSeveralNotes
        : _strings.banknoteNotRecognised;
    onResult(text);
    unawaited(AudioBus.instance.say(text, priority: SpeechPriority.answer));
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

  /// Says "hold still" only after the phone has been moving for a while.
  ///
  /// Movement itself is silent: the user may be walking. A sentence is only
  /// worth it when blurred frames are blocking the reading, or when object
  /// mode is scanning and needs a steady frame before it can describe one.
  void _noteMovement(DateTime now) {
    _movingSince ??= now;
    if (_interpretation != Interpretation.text &&
        _interpretation != Interpretation.object &&
        _interpretation != Interpretation.banknote) {
      return;
    }
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
    TextLayout layout,
    DateTime now,
    String text,
  ) {
    final audio = AudioBus.instance;
    if (audio.isMuted || audio.isSpeaking) return;

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
      if (!recentlySpoken && !alreadyRead && layout.wordCount > 0) {
        unawaited(Feedback.instance.toneFor(layout.coverage));
      }
      return;
    }

    onCue?.call(cue);
    if (kDebugMode) {
      debugPrint(
        'live: cue ${cue.name} centerX=${layout.centerX.toStringAsFixed(2)}',
      );
    }
    if (cue.pan != 0) {
      unawaited(Feedback.instance.aimProblem(pitch: cue.toneHz, pan: cue.pan));
    }
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
