import 'dart:async';

import 'package:camera/camera.dart';
// Flutter's Material library also defines a `Feedback` class (the haptic
// helper). Cue's own audio/haptic layer is the one this screen means.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Feedback;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/audio_bus.dart';
import '../core/cue_language.dart';
import '../core/cue_strings.dart';
import '../core/device_sensors.dart';
import '../core/feedback.dart';
import '../core/finder_request.dart';
import '../core/keep_awake.dart';
import '../core/location_service.dart';
import '../core/motion_monitor.dart';
import '../core/personal_items.dart';
import '../core/spoken_facts.dart';
import '../core/search_target.dart';
import '../core/tts_service.dart';
import '../core/voice_command.dart';
import '../core/voice_command_service.dart';
import '../core/voice_intro.dart';
import '../vision/camera_frame_encoder.dart';
import '../vision/frame_source.dart';
import '../vision/ocr_service.dart';
import '../vision/object_detect_service.dart';
import '../vision/detected_object.dart';
import '../vision/personal_item_vision.dart';
import '../core/object_labels.dart';
import '../core/object_preferences.dart';
import 'finder_dialog.dart';
import 'frame_pipeline.dart';
import 'frame_metrics.dart';
import 'object_box_painter.dart';
import 'scene_router.dart';
import 'teach_item_dialog.dart';

/// The five states from section 8 of the specification.
enum LivePhase { starting, searching, paused, error }

/// The live camera, its spoken actions, and the item finder.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with WidgetsBindingObserver {
  final PhoneCameraFrameSource _source = PhoneCameraFrameSource();
  late final FramePipeline _pipeline;
  final _itemStore = PersonalItemStore.instance;
  final _teachCamera = ValueNotifier<CameraController?>(null);
  Completer<CameraFrame?>? _teachFrame;
  bool _finderOpen = false;
  bool _teaching = false;

  /// The voice engine's readiness, kept so the first sentence can wait for the
  /// right voice without making the camera wait too.
  ///
  /// Binding the TTS engine and listing its voices takes seconds on some
  /// phones. Starting the camera behind that work made launch feel dead, so
  /// both now run at once and only speech waits.
  Future<CueLanguage>? _voiceReady;

  LivePhase _phase = LivePhase.starting;
  String? _error;
  String _lastResult = '';

  Timer? _searchTick;
  bool _starting = false;
  int _startToken = 0;
  bool _pausedByUser = false;

  /// Whether press-to-talk is currently listening.
  bool _listening = false;

  /// True while a "where am I" lookup is running, so repeated partial
  /// recognitions cannot stack several slow lookups.
  bool _locating = false;

  /// Whether developer mode is active: keeps camera preview bright and
  /// renders real-time object bounding boxes with confidence scores.
  bool _developerMode = false;

  void _toggleDeveloperMode() {
    setState(() {
      _developerMode = !_developerMode;
      _pipeline.developerMode = _developerMode;
      if (_developerMode) {
        _showPreview();
      }
    });
    Feedback.instance.gesture();
    final msg = _developerMode ? 'Developer mode on' : 'Developer mode off';
    unawaited(AudioBus.instance.say(msg, priority: SpeechPriority.navigation));
  }

  // --- Environment sensors --------------------------------------------------

  /// Light below this many lux, for this long, turns the torch on.
  static const double _darkLux = 12;
  static const Duration _darkDelay = Duration(seconds: 2);

  /// Light above this, for longer, turns the torch off again.
  /// Office-lit rooms are usually well above this, so a value of 120 was
  /// unreachable for a lot of users.
  static const double _brightLux = 50;
  static const Duration _brightDelay = Duration(seconds: 3);

  /// A torch left on is a battery drain and a public nuisance in a dark room,
  /// and the light sensor cannot see that a torch is needed (the torch itself
  /// raises the reading). It is therefore a short flash, not a lamp: the user
  /// can always say "torch on" again.
  static const Duration _torchMaxOn = Duration(seconds: 60);

  StreamSubscription<double>? _lightSubscription;
  StreamSubscription<bool>? _proximitySubscription;
  final _lightingSampler = FrameSampler();
  DateTime? _lastLightingFrame;
  double? _ambientLux;
  bool _sensorCovered = false;
  bool _manualTorchOff = false;
  bool _waitingForTorch = false;
  DateTime? _darkSince;
  DateTime? _brightSince;
  bool _torchOn = false;
  bool _torchAnnounced = false;
  DateTime? _torchOnSince;

  /// Whether the talk key is down, so a failed listen can retry while the user
  /// is still holding it.
  bool _talkKeyHeld = false;

  /// Set after the microphone is refused, so the explanation is said once.
  bool _micHintShown = false;

  /// True after the torch ran its full time in a room that stayed dark.
  ///
  /// The torch raises the light reading, so "dark" and "torch on" can be true
  /// at the same time. Without this flag Cue would switch the torch on again
  /// two seconds after timing out, forever.
  bool _torchTimedOut = false;

  /// Bumped whenever a listen is cancelled, so a late result cannot act after
  /// the app has paused or a newer listen has started.
  int _listenToken = 0;

  /// Raw pointer bookkeeping for the two-finger tap that starts a voice
  /// command. GestureDetector cannot count simultaneous pointers, so a
  /// Listener wrapped around it does the counting.
  final Set<int> _pointers = <int>{};
  final Map<int, Offset> _pointerOrigins = <int, Offset>{};
  int _maxPointers = 0;
  DateTime? _pointersDownAt;
  bool _pointersMoved = false;

  /// Whether the preview and the status panel are currently visible.
  ///
  /// The screen is for sighted helpers, not for the user. It shows itself for
  /// five seconds when a session starts and whenever a new reading lands, then
  /// fades to black: the camera keeps reading in the dark, which is better for
  /// privacy and for battery.
  bool _previewOn = true;
  Timer? _previewTimer;

  static const Duration _previewWindow = Duration(seconds: 5);

  /// Native volume-down long press arrives here. A physical key is easier to
  /// find than a multi-finger gesture and works under TalkBack.
  static const MethodChannel _keyChannel = MethodChannel('cue/keys');

  CueLanguage get _language => LanguageService.instance.language.value;

  CueStrings get _strings => CueStrings(_language);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final language = LanguageService.instance.language.value;
    _pipeline = FramePipeline(
      onResult: _onResult,
      language: language,
      waitingForTorch: () => _waitingForTorch,
      isTorchOn: () => _source.controller?.value.flashMode == FlashMode.torch,
    )..automaticDescriptions = ObjectPreferences.instance.automatic;
    unawaited(Feedback.instance.init());
    _keyChannel.setMethodCallHandler(_onHardwareKey);
    unawaited(_startSensors());
    unawaited(_prepareAndStart());

    // FR-04 / section 7: a soft tick every two seconds while searching.
    // Once a result has been read, the tick stops: an endless beep in the ear
    // is noise, and the aiming cues still speak up if the text is lost.
    _searchTick = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      final scanning =
          _pipeline.isSearchingForItem ||
          (_pipeline.interpretation != Interpretation.object &&
              _lastResult.isEmpty);
      if (_phase == LivePhase.searching &&
          scanning &&
          !_finderOpen &&
          !_teaching &&
          !_listening &&
          !AudioBus.instance.speaking.value) {
        unawaited(Feedback.instance.tick());
      }
    });
  }

  @override
  void dispose() {
    _finishTeachFrame(null);
    _teachCamera.dispose();
    _pipeline.reset();
    _searchTick?.cancel();
    _previewTimer?.cancel();
    _lightSubscription?.cancel();
    _proximitySubscription?.cancel();
    unawaited(MotionMonitor.instance.stop());
    unawaited(DeviceSensors.instance.stop());
    WidgetsBinding.instance.removeObserver(this);
    _startToken++;
    _listenToken++;
    _keyChannel.setMethodCallHandler(null);
    unawaited(KeepAwake.set(false));
    AudioBus.instance.unmute();
    unawaited(AudioBus.instance.stop());
    unawaited(VoiceCommandService.instance.cancel());
    unawaited(_source.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(MotionMonitor.instance.stop());
      unawaited(DeviceSensors.instance.stop());
      if (_phase != LivePhase.paused) {
        _pausedByUser = false;
        unawaited(_pause(announce: false));
      }
    } else if (state == AppLifecycleState.resumed) {
      unawaited(MotionMonitor.instance.start());
      unawaited(DeviceSensors.instance.start());
      if (_phase == LivePhase.paused && !_pausedByUser) {
        unawaited(_start());
      }
    }
  }

  /// Makes sure the voice and the chosen language agree before the camera
  /// starts.
  ///
  /// A phone can remember "Hindi" while having no Hindi voice installed. If
  /// the app started anyway, the first Hindi sentence would be read by an
  /// English engine, which sounds like nonsense and cannot be debugged by a
  /// blind user. Falling back here also switches OCR and speech recognition,
  /// so all three stay in one language.
  /// Starts the motion, light and proximity sensors.
  ///
  /// Safe to call again after a pause: the Dart subscriptions are created once
  /// and the native listeners are restarted by [DeviceSensors.start].
  Future<void> _startSensors() async {
    await MotionMonitor.instance.start();

    _lightSubscription ??= DeviceSensors.instance.light.listen(_onLight);
    _proximitySubscription ??= DeviceSensors.instance.proximityNear.listen(
      _onProximity,
    );

    await DeviceSensors.instance.start();

    if (kDebugMode) {
      final depth = await DeviceSensors.instance.depthAvailable();
      debugPrint(
        'sensors: depth output ${depth ? 'available' : 'not available'}',
      );
    }
  }

  /// Applies a torch request spoken as a voice command.
  Future<void> _torchFromVoice(bool on) async {
    _torchTimedOut = false;
    _manualTorchOff = !on;
    if (!on) _waitingForTorch = false;
    await _setTorch(on);
    if (!mounted) return;
    unawaited(
      AudioBus.instance.say(
        _source.controller == null ||
                (_source.controller!.value.flashMode == FlashMode.torch) != on
            ? _strings.torchUnavailable
            : on
            ? _strings.torchTurnedOn
            : _strings.torchTurnedOff,
        priority: SpeechPriority.navigation,
      ),
    );
  }

  /// Speaks the current time, because the phone already knows it.
  Future<void> _sayTime() async {
    await AudioBus.instance.say(
      spokenTime(DateTime.now(), hindi: _language.isHindi),
      priority: SpeechPriority.answer,
    );
  }

  /// Speaks today's date.
  Future<void> _sayDate() async {
    await AudioBus.instance.say(
      spokenDate(DateTime.now(), hindi: _language.isHindi),
      priority: SpeechPriority.answer,
    );
  }

  /// Answers "what mode am I in?" without changing anything.
  Future<void> _sayMode() async {
    final mode = _pipeline.interpretation;
    final text = mode.isBuilt
        ? _strings.modeAnswer(mode.label)
        : _strings.notBuilt(_strings.modeName(mode.label));
    await AudioBus.instance.say(text, priority: SpeechPriority.answer);
  }

  Future<void> _sayLanguage() async {
    await AudioBus.instance.say(
      _strings.languageAnswer,
      priority: SpeechPriority.answer,
    );
  }

  Future<void> _sayTorchState() async {
    await AudioBus.instance.say(
      _strings.torchStateAnswer(_torchOn),
      priority: SpeechPriority.answer,
    );
  }

  Future<void> _saySpeed() async {
    final tts = TtsService.instance;
    await AudioBus.instance.say(
      _strings.speedAnswer(slowest: tts.atSlowest, fastest: tts.atFastest),
      priority: SpeechPriority.answer,
    );
  }

  Future<void> _sayBattery() async {
    final percent = await DeviceSensors.instance.batteryPercent();
    if (!mounted) return;
    await AudioBus.instance.say(
      spokenBattery(percent, hindi: _language.isHindi),
      priority: SpeechPriority.answer,
    );
  }

  /// Answers "where was I?" and "how much is left?".
  Future<void> _sayReadingProgress() async {
    final bus = AudioBus.instance;
    if (bus.sentenceCount == 0) {
      await AudioBus.instance.say(
        _strings.nothingToRead,
        priority: SpeechPriority.answer,
      );
      return;
    }

    await AudioBus.instance.say(
      spokenReadingProgress(
        index: bus.sentenceIndex + 1,
        total: bus.sentenceCount,
        hindi: _language.isHindi,
      ),
      priority: SpeechPriority.answer,
    );
  }

  /// Samples the middle of the view and names its colour.
  Future<void> _sayColourInView() async {
    final reading = await _pipeline.colourInView();
    if (!mounted) return;
    await AudioBus.instance.say(
      colourInViewAnswer(reading, hindi: _language.isHindi),
      priority: SpeechPriority.answer,
    );
  }

  /// Answers "what is on my left/right?" with one object, not a whole scene.
  Future<void> _saySide(ObjectDirection side) async {
    final hindi = _language.isHindi;

    // Start the scan before the preamble so the answer is not delayed by the
    // preamble's own speaking time.
    final scan = _pipeline.objectOn(side);
    unawaited(
      AudioBus.instance.say(
        sideLooking(side, hindi: hindi),
        priority: SpeechPriority.info,
      ),
    );

    final object = await scan;
    if (!mounted) return;

    final description = object == null
        ? nothingOnSide(side, hindi: hindi)
        : objectDescription(
            <DetectedObject>[object],
            hindi: hindi,
            includeDistance: false,
          );
    // Hindi is frozen and has no generic label for an ambiguous object, so a
    // description can come back empty. The existing "unrecognised object" line
    // is honest and needs no new string.
    final text = description.isEmpty ? _strings.somethingThere : description;
    await AudioBus.instance.say(text, priority: SpeechPriority.answer);
  }

  Future<void> _repeatAnswer() async {
    unawaited(Feedback.instance.gesture());
    await AudioBus.instance.repeatAnswer();
  }

  /// "Never mind" stops what is happening and says only "Okay".
  ///
  /// It must not guess at an action: the point of the phrase is that the user
  /// withdrew the request.
  Future<void> _handleNeverMind() async {
    _pipeline.stopItemSearch();
    await AudioBus.instance.stop();
    await AudioBus.instance.say(
      _strings.neverMind,
      priority: SpeechPriority.navigation,
    );
  }

  /// Asks the phone for a position and speaks it.
  ///
  /// A fix can take a few seconds, so the user is told the wait is deliberate.
  /// The camera keeps running meanwhile; only the voice is busy.
  Future<void> _sayLocation() async {
    // A "where" partial and then the full sentence fire this twice while the
    // first lookup is still waiting. Stacking lookups made the user wait for
    // two or three answers in a row, so only one may run at a time.
    if (_locating) {
      debugPrint('location: already looking');
      return;
    }
    _locating = true;
    try {
      await _askForLocation();
    } finally {
      _locating = false;
    }
  }

  Future<void> _askForLocation() async {
    final hindi = _language.isHindi;

    // The phone-wide switch comes first. If it is off, no permission or
    // provider can produce a fix, and telling the user to move near a window
    // would be untrue. Say what is wrong and take them to the switch.
    final servicesOn = await LocationService.instance.servicesEnabled();
    if (!mounted) return;
    // Field diagnostics: "it said nothing" is otherwise impossible to check.
    debugPrint('location: services=$servicesOn');
    if (!servicesOn) {
      debugPrint('location: problem=servicesOff fix=false');
      await AudioBus.instance.say(
        spokenLocation(
          const LocationResult(null, LocationProblem.servicesOff),
          hindi: hindi,
        ),
        priority: SpeechPriority.answer,
      );
      if (!mounted) return;
      await LocationService.instance.openLocationSettings();
      return;
    }

    // The system permission dialog is silent, so a blind user would otherwise
    // get an unexplained interruption. Explain first, then let the dialog
    // appear.
    final needsPermission = await LocationService.instance.needsPermission();
    if (!mounted) return;
    if (needsPermission) {
      await AudioBus.instance.say(
        hindi
            ? 'लोकेशन के लिए अनुमति चाहिए। अगली स्क्रीन पर अनुमति दें चुनें।'
            : 'Location needs permission. On the next screen, choose Allow.',
        priority: SpeechPriority.answer,
      );
      if (!mounted) return;
    }

    await AudioBus.instance.say(
      hindi
          ? 'लोकेशन देख रहा हूँ। कुछ सेकंड लग सकते हैं।'
          : 'Finding your location. This may take a few seconds.',
      priority: SpeechPriority.answer,
    );
    if (!mounted) return;

    // Silence for ten seconds sounds like a failure. A quiet nudge keeps the
    // user informed without drowning out the answer if it arrives first.
    final nudge = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      unawaited(
        AudioBus.instance.say(
          hindi
              ? 'अभी भी लोकेशन देख रहा हूँ।'
              : 'Still looking for your location.',
          priority: SpeechPriority.answer,
        ),
      );
    });

    // A long window is deliberate: indoors the fused provider often needs ten
    // seconds to combine Wi-Fi and cell signals into a fix.
    final result = await LocationService.instance.current(
      timeout: const Duration(seconds: 12),
    );
    nudge.cancel();
    if (!mounted) return;
    debugPrint(
      'location: problem=${result.problem.name} fix=${result.fix != null}',
    );
    await AudioBus.instance.say(
      spokenLocation(result, hindi: hindi),
      priority: SpeechPriority.answer,
    );

    // A blocked permission can only be fixed in Cue's settings page, so open
    // it rather than leaving the user to find it.
    if (result.problem == LocationProblem.permissionBlocked && mounted) {
      await LocationService.instance.openAppSettingsPage();
    }
  }

  /// Opens the screen where the phone's Location switch lives.
  Future<void> _openLocationSettings() async {
    await AudioBus.instance.say(
      _language.isHindi
          ? 'लोकेशन सेटिंग खोल रहा हूँ।'
          : 'Opening location settings.',
      priority: SpeechPriority.answer,
    );
    if (!mounted) return;
    await LocationService.instance.openLocationSettings();
  }

  void _onLight(double lux) {
    if (lux.isFinite && lux >= 0) _ambientLux = lux;
  }

  void _onCameraFrame(CameraFrame frame) {
    final now = DateTime.now();
    if (mounted &&
        _phase == LivePhase.searching &&
        (_lastLightingFrame == null ||
            now.difference(_lastLightingFrame!) >=
                const Duration(milliseconds: 300))) {
      _lastLightingFrame = now;
      _updateLighting(frame, now);
    }
    if (_teaching) {
      _finishTeachFrame(frame);
      return;
    }
    if (_finderOpen) return;
    _pipeline.handleFrame(frame);
  }

  void _updateLighting(CameraFrame frame, DateTime now) {
    final lux = _ambientLux;
    _waitingForTorch = false;
    if (_torchOn &&
        _torchOnSince != null &&
        now.difference(_torchOnSince!) >= _torchMaxOn) {
      _torchTimedOut = true;
      unawaited(_setTorch(false, autoOff: true));
      return;
    }

    if (lux == null || _sensorCovered) {
      _darkSince = null;
      _brightSince = null;
      return;
    }
    if (lux < _darkLux) {
      _brightSince = null;
      if (_torchOn ||
          _torchTimedOut ||
          _manualTorchOff ||
          !_lightingSampler.sample(frame.image).isTooDark) {
        _darkSince = null;
        return;
      }
      _waitingForTorch = true;
      _darkSince ??= now;
      if (now.difference(_darkSince!) >= _darkDelay) {
        unawaited(_setTorch(true, announce: !_torchAnnounced));
      }
      return;
    }

    _darkSince = null;
    // A room that is actually lit clears the timeout, so the next dark room
    // can have its own flash.
    if (lux > _brightLux) _torchTimedOut = false;
    if (_torchOn && lux > _brightLux) {
      _brightSince ??= now;
      if (now.difference(_brightSince!) >= _brightDelay) {
        unawaited(_setTorch(false));
      }
    } else {
      _brightSince = null;
    }
  }

  /// Silences Cue while the phone is covered, and reopens its voice after.
  void _onProximity(bool near) {
    _sensorCovered = near;
    if (!mounted || _listening) return;
    if (kDebugMode) {
      debugPrint('live: proximity near=$near');
    }
    if (near) {
      AudioBus.instance.mute();
    } else {
      AudioBus.instance.unmute();
    }
  }

  Future<void> _setTorch(
    bool on, {
    bool announce = false,
    bool autoOff = false,
  }) async {
    if (_torchOn == on) return;
    _torchOn = on;
    _torchOnSince = on ? DateTime.now() : null;
    await _source.setTorch(on);
    if (!mounted) return;

    _torchOn = _source.controller?.value.flashMode == FlashMode.torch;
    if (_torchOn != on) {
      if (on) _torchTimedOut = true;
      return;
    }
    if (!on) {
      _torchAnnounced = false;
      if (autoOff) {
        unawaited(
          AudioBus.instance.say(
            _strings.torchAutoOff,
            priority: SpeechPriority.navigation,
          ),
        );
      }
      return;
    }
    if (announce) {
      _torchAnnounced = true;
      unawaited(
        AudioBus.instance.say(
          _strings.torchOn,
          priority: SpeechPriority.navigation,
        ),
      );
    }
  }

  Future<void> _prepareAndStart() async {
    // The camera comes first: the preview, the aiming cues and the reading
    // all come from it, and on this app's phones the voice engine can take
    // several seconds to bind. Waiting for it made launch look broken.
    _voiceReady = _prepareLanguage();
    unawaited(_start());
  }

  /// Applies the saved language as soon as the voice engine can answer for it.
  ///
  /// Runs in parallel with the camera. Anything that speaks must await
  /// [_voiceReady] first, or it could read in the old language after a
  /// session-only fallback.
  Future<CueLanguage> _prepareLanguage() async {
    CueLanguage voiceLanguage;
    try {
      voiceLanguage = await TtsService.instance.prepareLanguage();
    } catch (_) {
      // A voice-engine failure must not break the session: keep the saved
      // language and let the camera and OCR carry on.
      voiceLanguage = LanguageService.instance.language.value;
    }
    if (!mounted) return voiceLanguage;

    if (voiceLanguage != LanguageService.instance.language.value) {
      // Session-only fallback. Persisting this would erase the user's saved
      // Hindi choice just because this launch had no Hindi voice.
      await LanguageService.instance.set(voiceLanguage, persist: false);
      _pipeline.setLanguage(voiceLanguage);
      // The saved script has no voice on this phone; load the fallback's
      // recogniser before the first reading needs it.
      unawaited(OcrService.instance.warmUp(voiceLanguage));
      if (mounted) setState(() {});
    }

    return voiceLanguage;
  }

  String _cameraErrorMessage(CameraStartError error) {
    switch (error) {
      case CameraStartError.permissionDenied:
        return _strings.cameraPermissionDenied;
      case CameraStartError.permissionBlocked:
        return _strings.cameraPermissionBlocked;
      case CameraStartError.noCamera:
        return _strings.cameraNoDevice;
      case CameraStartError.couldNotStart:
        return _strings.cameraCouldNotStart;
    }
  }

  Future<void> _start() async {
    if (_starting || _phase == LivePhase.searching) return;

    // Coming back from a pause is a deliberate act, so the page in view should
    // be read again even if it was already spoken before the pause.
    final restarting = _phase == LivePhase.paused || _phase == LivePhase.error;

    _starting = true;
    final token = ++_startToken;
    if (mounted) {
      setState(() {
        _phase = LivePhase.starting;
        _error = null;
      });
    }

    final startError = await _source.start(onFrame: _onCameraFrame);

    if (!mounted || token != _startToken) {
      _starting = false;
      if (startError == null) await _source.stop();
      return;
    }

    _starting = false;

    if (startError != null) {
      final message = _cameraErrorMessage(startError);
      setState(() {
        _phase = LivePhase.error;
        _error = message;
      });
      unawaited(Feedback.instance.error());
      unawaited(AudioBus.instance.say(message, priority: SpeechPriority.alert));
      return;
    }

    _pipeline.reset();
    if (_teaching) _teachCamera.value = _source.controller;
    setState(() {
      _phase = LivePhase.searching;
      if (restarting) {
        // A restarted session reads the page in view again; the caption must
        // not keep showing the previous session's reading.
        _lastResult = '';
        AudioBus.instance.forgetLastResult();
      }
    });

    // The camera is open, so the OCR model can load now without delaying it.
    // Starting this before the camera was what made launch slow: ML Kit's
    // first load stalls the main thread for seconds.
    unawaited(OcrService.instance.warmUp(_language));

    // The display must not time out mid-page: a locked screen backgrounds the
    // app and the camera stops without a word.
    unawaited(KeepAwake.set(true));
    _showPreview();
    if (!_teaching && !_finderOpen) {
      unawaited(Feedback.instance.ready());
      unawaited(_announceReady(token));
    }
    unawaited(_prepareVoice());
  }

  /// Asks for the microphone and warms the recogniser before the first press.
  ///
  /// Without this, the permission dialog only appears after the user has
  /// already held volume down and started speaking, so the command is lost and
  /// the screen looks broken. A blind user also cannot read the dialog, so the
  /// reason is spoken first.
  Future<void> _prepareVoice() async {
    // The recogniser is set to the user's language, so it must wait until the
    // voice engine has settled the language (and any fallback) first.
    final ready = _voiceReady;
    if (ready != null) await ready;
    if (!mounted) return;

    final status = await Permission.microphone.status;
    if (status.isGranted) {
      await VoiceCommandService.instance.prepare();
      return;
    }

    if (status.isPermanentlyDenied) {
      await _sayMicBlockedOnce();
      return;
    }

    if (!mounted) return;
    await AudioBus.instance.say(
      _strings.microphoneAsk,
      priority: SpeechPriority.navigation,
    );

    final asked = await Permission.microphone.request();
    if (asked.isGranted) {
      await VoiceCommandService.instance.prepare();
      return;
    }
    await _sayMicBlockedOnce();
  }

  /// Explains a refused microphone once per session, not on every start.
  Future<void> _sayMicBlockedOnce() async {
    if (_micHintShown) return;
    _micHintShown = true;
    await AudioBus.instance.say(
      _strings.microphoneBlocked,
      priority: SpeechPriority.navigation,
    );
  }

  /// Shows the preview and the status for a few seconds, then lets them fade.
  ///
  /// Called on start, on a new reading, on a manual read, and from the actions
  /// menu. Nothing depends on it: the pipeline keeps running when the screen is
  /// black.
  void _showPreview() {
    _previewTimer?.cancel();
    if (!mounted) return;
    if (!_previewOn) setState(() => _previewOn = true);
    if (_developerMode) return;
    _previewTimer = Timer(_previewWindow, () {
      if (!mounted) return;
      if (_developerMode) return;
      // Do not go dark in the middle of a reading: a sighted helper following
      // the caption gets the whole sentence, then the screen fades.
      if (AudioBus.instance.reading.value || _pipeline.isSearchingForItem) {
        _showPreview();
        return;
      }
      setState(() => _previewOn = false);
    });
  }

  Future<void> _announceReady(int token) async {
    // Let the rising tone finish before the voice starts.
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted || token != _startToken || _phase != LivePhase.searching) {
      return;
    }

    // The camera no longer waits for the voice engine, so the intro does.
    // Otherwise a saved Hindi choice with no Hindi voice would be spoken in
    // English before the session fallback could take effect.
    final ready = _voiceReady;
    if (ready != null) await ready;
    if (!mounted || token != _startToken || _phase != LivePhase.searching) {
      return;
    }

    // Explain the physical talk key once, on Android, then stop repeating it.
    final intro =
        defaultTargetPlatform == TargetPlatform.android &&
        await voiceIntroNeeded();
    if (!mounted || token != _startToken || _phase != LivePhase.searching) {
      return;
    }

    await AudioBus.instance.say(
      intro ? _strings.lookingIntro : _strings.looking,
      priority: SpeechPriority.info,
    );
    if (intro) unawaited(markVoiceIntroSeen());
  }

  Future<void> _pause({bool announce = true}) async {
    _startToken++;
    _starting = false;
    _previewTimer?.cancel();
    _cancelVoice();
    _finishTeachFrame(null);
    final hadTeachPreview = _teachCamera.value != null;
    _teachCamera.value = null;

    // The preview must leave the tree before the controller is disposed.
    // CameraPreview keeps listening to its controller, so disposing under a
    // still-mounted preview makes it rebuild and throw.
    if (mounted && (_previewOn || hadTeachPreview)) {
      setState(() => _previewOn = false);
      await WidgetsBinding.instance.endOfFrame;
    } else {
      _previewOn = false;
    }

    await KeepAwake.set(false);
    await AudioBus.instance.stop();
    await _source.stop();
    // Stopping the camera turns the torch off with it; the bookkeeping has to
    // agree or a later dark room would never switch it back on.
    _torchOn = false;
    _torchAnnounced = false;
    _torchOnSince = null;
    _torchTimedOut = false;
    _waitingForTorch = false;
    _lastLightingFrame = null;
    _darkSince = null;
    _brightSince = null;
    _pipeline.reset();

    if (!mounted) return;
    setState(() => _phase = LivePhase.paused);

    if (announce) {
      unawaited(Feedback.instance.paused());
      unawaited(
        AudioBus.instance.say(
          _strings.paused,
          priority: SpeechPriority.navigation,
        ),
      );
    }
  }

  /// The one activation gesture. With TalkBack on, a double-tap on the focused
  /// full-screen node arrives here as a semantic tap; without TalkBack, the
  /// GestureDetector's double-tap does the same thing.
  void _activate() {
    if (_finderOpen || _teaching) return;
    if (_listening) {
      // A second double-tap while listening cancels the listen instead of
      // starting a reading the microphone would hear.
      _cancelVoice();
      return;
    }

    unawaited(Feedback.instance.gesture());

    if (_phase == LivePhase.paused || _phase == LivePhase.error) {
      _pausedByUser = false;
      unawaited(_start());
      return;
    }

    if (_phase == LivePhase.searching) {
      // A paused reading owns the double tap: resume where it stopped instead
      // of re-reading the page and forgetting the place.
      if (AudioBus.instance.readingPaused) {
        unawaited(_handleResume());
        return;
      }

      _pipeline.requestManualRead();
      _showPreview();
      if (_pipeline.interpretation == Interpretation.text &&
          !AudioBus.instance.speaking.value) {
        unawaited(
          AudioBus.instance.say(
            _strings.readingNow,
            priority: SpeechPriority.info,
          ),
        );
      }
    }
  }

  void _repeat() {
    unawaited(Feedback.instance.gesture());
    unawaited(AudioBus.instance.repeatLast());
  }

  void _announceFinder(String message) {
    unawaited(AudioBus.instance.say(message, priority: SpeechPriority.answer));
  }

  bool _finderReady() {
    if (_phase == LivePhase.searching &&
        _source.controller?.value.isInitialized == true) {
      return true;
    }
    _announceFinder(_strings.finderUnavailable);
    return false;
  }

  Future<void> _chooseItem({String initialName = ''}) async {
    if (_finderOpen || _teaching || !_finderReady()) return;
    setState(() {
      _finderOpen = true;
      if (initialName.isEmpty && _pipeline.isSearchingForItem) {
        _lastResult = _strings.searchStopped;
      }
      _pipeline.reset();
    });
    FinderRequest? request;
    try {
      await AudioBus.instance.stop();
      var items = const <PersonalItem>[];
      var storageUnavailable = false;
      try {
        items = await _itemStore.read();
      } catch (_) {
        storageUnavailable = true;
      }
      if (!mounted || _phase != LivePhase.searching) return;
      final dialog = showDialog<FinderRequest>(
        context: context,
        builder: (context) => FinderDialog(
          strings: _strings,
          items: items,
          sayName: _listenForItemName,
          removeItem: _itemStore.forget,
          announce: _announceFinder,
          initialName: initialName,
          storageUnavailable: storageUnavailable,
        ),
      );
      if (initialName.isNotEmpty) _announceFinder(_strings.unrecognizedItem);
      request = await dialog;
    } finally {
      _finderOpen = false;
      if (mounted && _listening) _cancelVoice();
    }
    if (mounted && request != null) await _runFinderRequest(request);
  }

  Future<void> _runFinderRequest(FinderRequest request) async {
    if (!mounted || _finderOpen || _teaching) return;
    if (request.action == FinderAction.teach) {
      await _teachItem(request.name);
      return;
    }
    if (request.commonTarget case final target?) {
      _findItem(target);
      return;
    }
    if (request.name.isEmpty) {
      await _chooseItem();
      return;
    }
    if (!_finderReady()) return;
    final common = builtInFinderTarget(request.name);
    PersonalItem? personal;
    try {
      personal = taughtFinderItem(await _itemStore.read(), request.name);
    } catch (_) {
      if (!mounted) return;
      if (common == null) {
        _announceFinder(_strings.itemStoreError);
        return;
      }
    }
    if (!mounted || _finderOpen || _teaching || !_finderReady()) return;
    if (personal case final profile?) {
      _startFinding(
        _strings.searchingNamedItem(profile.name),
        () => _pipeline.startPersonalItemSearch(profile),
      );
    } else if (common != null) {
      _findItem(common);
    } else {
      final message = _strings.unrecognizedItem;
      _onResult(message);
      await _chooseItem(initialName: request.name);
    }
  }

  void _findItem(SearchTarget target) {
    if (!_finderReady()) return;
    unawaited(ObjectDetectService.instance.warmUp());
    _startFinding(
      _strings.searchingItem(target),
      () => _pipeline.startItemSearch(target),
    );
  }

  void _startFinding(String message, VoidCallback start) {
    setState(() {
      start();
      _lastResult = message;
    });
    _showPreview();
    _announceFinder(message);
  }

  Future<void> _teachItem(String name) async {
    if (_finderOpen || _teaching || !_finderReady()) return;
    setState(() {
      _teaching = true;
      if (_pipeline.isSearchingForItem) _lastResult = _strings.searchStopped;
      _pipeline.reset();
    });
    _teachCamera.value = _source.controller;
    PersonalItem? saved;
    try {
      await AudioBus.instance.stop();
      final items = await _itemStore.read();
      if (!mounted || _phase != LivePhase.searching) return;
      saved = await showDialog<PersonalItem>(
        context: context,
        barrierDismissible: false,
        builder: (context) => TeachItemDialog(
          strings: _strings,
          camera: _teachCamera,
          items: items,
          sayName: _listenForItemName,
          capture: _capturePersonalExample,
          save: _itemStore.save,
          announce: _announceFinder,
          initialName: name,
        ),
      );
    } catch (_) {
      if (mounted) _announceFinder(_strings.itemStoreError);
    } finally {
      if (mounted) {
        _finishTeachFrame(null);
        _teachCamera.value = null;
        setState(() => _teaching = false);
        if (_listening) _cancelVoice();
      }
    }
    if (!mounted || saved == null) return;
    final message = _strings.itemTaught(saved.name);
    _onResult(message);
    unawaited(Feedback.instance.found());
    _announceFinder(message);
  }

  void _finishTeachFrame(CameraFrame? frame) {
    final pending = _teachFrame;
    _teachFrame = null;
    pending?.complete(frame);
  }

  Future<PersonalExample> _capturePersonalExample() async {
    final controller = _teachCamera.value;
    if (!_teaching || controller == null || _teachFrame != null) {
      throw StateError('No camera available for teaching');
    }
    final pending = Completer<CameraFrame?>();
    _teachFrame = pending;
    final frame = await pending.future
        .timeout(const Duration(seconds: 3), onTimeout: () => null)
        .whenComplete(() {
          if (identical(_teachFrame, pending)) _teachFrame = null;
        });
    if (frame == null) throw StateError('No teaching frame received');
    final rotation = rotationDegrees(
      frame.description,
      frame.deviceOrientation,
    );
    final jpeg = await cameraFrameToJpeg(frame, rotation);
    final example = await const PersonalItemVision().capture(
      jpeg,
      uprightSize(frame.image.width, frame.image.height, rotation),
    );
    if (!mounted || !identical(controller, _teachCamera.value)) {
      throw StateError('Camera changed while capturing the example');
    }
    return example;
  }

  void _stopSpeech() {
    if (_pipeline.stopItemSearch()) {
      setState(() => _lastResult = _strings.searchStopped);
      unawaited(
        AudioBus.instance.say(
          _strings.searchStopped,
          priority: SpeechPriority.answer,
        ),
      );
      return;
    }
    unawaited(Feedback.instance.gesture());
    unawaited(AudioBus.instance.stop());
  }

  void _help() {
    unawaited(Feedback.instance.gesture());
    unawaited(
      AudioBus.instance.say(
        _pipeline.interpretation == Interpretation.object
            ? _strings.objectHelp
            : _strings.help,
        priority: SpeechPriority.navigation,
      ),
    );
  }

  /// Steps the voice speed and confirms the change by speaking at the new
  /// rate. The confirmation is the sample: the user hears the pace rather
  /// than a number they would have to translate.
  Future<void> _changeSpeed({required bool faster}) async {
    unawaited(Feedback.instance.gesture());

    // A rate change only affects the next sentence. Stop whatever is being
    // said so the confirmation is the first thing heard at the new pace —
    // otherwise the user changes speed and the old sentence carries on, which
    // sounds as if the action did nothing.
    await AudioBus.instance.stop();

    final service = TtsService.instance;
    final changed = faster ? await service.faster() : await service.slower();

    if (!changed) {
      await AudioBus.instance.say(
        faster ? _strings.fastest : _strings.slowest,
        priority: SpeechPriority.navigation,
      );
      await _sayReadingPausedHint();
      return;
    }

    await AudioBus.instance.say(
      faster ? _strings.fasterConfirmation : _strings.slowerConfirmation,
      priority: SpeechPriority.navigation,
    );
    await _sayReadingPausedHint();
  }

  void _slowerSpeech() {
    unawaited(_changeSpeed(faster: false));
  }

  void _fasterSpeech() {
    unawaited(_changeSpeed(faster: true));
  }

  void _nextInterpretation() {
    unawaited(_changeInterpretation(forward: true));
  }

  /// Changes the handler with a sideways swipe.
  ///
  /// The four choices come from section 7 of the specification. Only text has
  /// an implementation, and the app says so rather than pretending a detector
  /// exists. The announcement is a control, so it stops the old reading first
  /// and is then heard at navigation priority.
  Future<void> _changeInterpretation({required bool forward}) async {
    final current = _pipeline.interpretation;
    await _setInterpretation(forward ? current.next : current.previous);
  }

  /// Switches to [next] and announces the result.
  Future<void> _setInterpretation(Interpretation next) async {
    unawaited(Feedback.instance.gesture());
    await AudioBus.instance.stop();

    if (!next.isBuilt) {
      await AudioBus.instance.say(
        _strings.notBuilt(_strings.modeName(next.label)),
        priority: SpeechPriority.navigation,
      );
      return;
    }
    if (next == Interpretation.object) {
      // Load the detector when the mode is chosen, not at launch: warming a
      // 10 MB model on a cold start competes with the camera and OCR, and
      // most sessions never leave text mode.
      unawaited(ObjectDetectService.instance.warmUp());
    }
    if (!mounted) return;
    setState(() => _pipeline.setInterpretation(next));
    AudioBus.instance.forgetLastResult();
    _showPreview();

    // One line per mode change is cheap and makes on-device support possible
    // without a debug build.
    if (kDebugMode) {
      debugPrint('live: interpretation ${next.name}');
    }

    final firstVisit = ObjectPreferences.instance.firstVisit(next.name);
    final announcement = !firstVisit
        ? '${_strings.modeName(next.label)} ${_language.isHindi ? 'मोड।' : 'mode.'}'
        : switch (next) {
            Interpretation.text => _strings.textModeAnnouncement,
            Interpretation.object => _strings.objectModeAnnouncement,
            Interpretation.banknote => _strings.banknoteModeAnnouncement,
            Interpretation.screen => _strings.notBuilt(
              _strings.modeName(next.label),
            ),
          };
    await AudioBus.instance.say(
      announcement,
      priority: SpeechPriority.navigation,
    );
  }

  void _setAutoDescriptions(bool enabled) {
    ObjectPreferences.instance.setAutomatic(enabled);
    setState(() => _pipeline.automaticDescriptions = enabled);
    unawaited(
      AudioBus.instance.say(
        _strings.autoDescriptions(enabled),
        priority: SpeechPriority.navigation,
      ),
    );
  }

  Future<void> _nextSentence() async {
    await _announceMove(await AudioBus.instance.nextSentence());
  }

  Future<void> _previousSentence() async {
    await _announceMove(await AudioBus.instance.previousSentence());
  }

  Future<void> _startOver() async {
    await _announceMove(await AudioBus.instance.startOver());
  }

  Future<void> _announceMove(ReadingMove move) async {
    switch (move) {
      case ReadingMove.moved:
        break;
      case ReadingMove.atStart:
        await AudioBus.instance.say(
          _strings.startOfPage,
          priority: SpeechPriority.navigation,
        );
      case ReadingMove.atEnd:
        await AudioBus.instance.say(
          _strings.endOfPage,
          priority: SpeechPriority.navigation,
        );
      case ReadingMove.noReading:
        await AudioBus.instance.say(
          _strings.nothingToRead,
          priority: SpeechPriority.navigation,
        );
    }
  }

  /// "Pause" first pauses the reading. Only when nothing is being read does it
  /// fall back to pausing the camera, which is what the old build did for
  /// every pause and why the command felt wrong.
  Future<void> _handlePause() async {
    unawaited(Feedback.instance.gesture());

    if (await AudioBus.instance.pauseReading()) {
      await AudioBus.instance.say(
        _strings.readingPaused,
        priority: SpeechPriority.navigation,
      );
      if (mounted) setState(() {});
      return;
    }

    if (_phase == LivePhase.searching) {
      _pausedByUser = true;
      await _pause();
      return;
    }

    await AudioBus.instance.say(
      _strings.alreadyPaused,
      priority: SpeechPriority.navigation,
    );
  }

  Future<void> _handleResume() async {
    unawaited(Feedback.instance.gesture());

    if (await AudioBus.instance.resumeReading()) {
      if (mounted) setState(() {});
      return;
    }

    if (_phase == LivePhase.paused || _phase == LivePhase.error) {
      _pausedByUser = false;
      await _start();
      return;
    }

    await AudioBus.instance.say(
      _strings.alreadyRunning,
      priority: SpeechPriority.navigation,
    );
  }

  /// Switches OCR, voice output and speech recognition together.
  ///
  /// If the phone has no Hindi voice, Cue stays in English instead of reading
  /// Devanagari with an English voice. That failure is spoken plainly, because
  /// a half-switched language would sound like a broken reading.
  Future<void> _setLanguage(CueLanguage language) async {
    if (language == _language) {
      await AudioBus.instance.say(
        language.isHindi ? _strings.alreadyHindi : _strings.alreadyEnglish,
        priority: SpeechPriority.navigation,
      );
      return;
    }

    unawaited(Feedback.instance.gesture());
    await AudioBus.instance.stop();

    final voiceReady = await TtsService.instance.setLanguage(language);
    if (!voiceReady) {
      await AudioBus.instance.say(
        language.isHindi
            ? _strings.hindiVoiceMissing
            : _strings.englishVoiceMissing,
        priority: SpeechPriority.alert,
      );
      return;
    }

    await LanguageService.instance.set(language);
    _pipeline.setLanguage(language);
    AudioBus.instance.forgetLastResult();
    unawaited(OcrService.instance.warmUp(language));
    _showPreview();

    if (!mounted) return;
    setState(() {});

    final strings = CueStrings(language);
    await AudioBus.instance.say(
      language.isHindi ? strings.switchedToHindi : strings.switchedToEnglish,
      priority: SpeechPriority.navigation,
    );
  }

  void _toggleLanguage() {
    unawaited(
      _setLanguage(_language.isHindi ? CueLanguage.english : CueLanguage.hindi),
    );
  }

  /// Cancels a listen and makes sure a late result is ignored.
  void _cancelVoice() {
    _listenToken++;
    AudioBus.instance.unmute();
    if (_listening) {
      _listening = false;
      if (mounted) setState(() {});
    }
    unawaited(VoiceCommandService.instance.cancel());
  }

  /// Handles the native volume-down long press.
  Future<dynamic> _onHardwareKey(MethodCall call) async {
    debugPrint('voice: key ${call.method}');
    switch (call.method) {
      case 'talkStart':
        if (_finderOpen || _teaching) return null;
        _talkKeyHeld = true;
        // A press while the previous listen is still ending is the user
        // retrying. Ignoring it made Cue feel dead for up to a second after a
        // failed command, and a retry is exactly what a blind user does.
        if (_listening) _restartVoice();
        unawaited(_listenForCommand());
      case 'talkEnd':
        _talkKeyHeld = false;
        unawaited(VoiceCommandService.instance.finishListening());
    }
    return null;
  }

  /// Drops the current listen and makes room for a fresh one.
  ///
  /// The token bump is what stops the old attempt's cleanup from unmuting the
  /// voice or clearing the "Listening" state of the attempt that replaces it.
  void _restartVoice() {
    _listenToken++;
    AudioBus.instance.unmute();
    _listening = false;
    if (mounted) setState(() {});
    unawaited(VoiceCommandService.instance.cancel());
  }

  /// Says the "Reading paused" hint once after an action that parked a page.
  ///
  /// A blind user who asked for help or a slower voice should not be left in
  /// silence wondering where the page went.
  Future<void> _sayReadingPausedHint() async {
    if (!mounted) return;
    if (!AudioBus.instance.takeReadingPauseHint()) return;
    await AudioBus.instance.say(
      _strings.readingPaused,
      priority: SpeechPriority.navigation,
    );
  }

  /// One press-to-talk attempt.
  ///
  /// Nothing is spoken before listening: the microphone would hear it. A short
  /// rising tone and vibration tell the user that Cue is ready for a command.
  Future<void> _listenForCommand() async {
    if (_finderOpen || _teaching) return;
    final result = await _listen();
    if (result == null) return;
    await _runVoiceResult(result);
    await _sayReadingPausedHint();
  }

  Future<String?> _listenForItemName() async {
    final result = await _listen(dictation: true);
    if (!mounted || result == null) return null;
    if (result.ok) return result.words;
    unawaited(Feedback.instance.notHeard());
    _announceFinder(
      result.problem == VoiceProblem.noSpeech ||
              result.problem == VoiceProblem.noMatch
          ? _strings.nameNotHeard
          : _voiceProblemMessage(result.problem),
    );
    return null;
  }

  Future<VoiceCommandResult?> _listen({bool dictation = false}) async {
    if (_listening) return null;
    final token = ++_listenToken;
    final startedByKey = _talkKeyHeld && !dictation;
    setState(() => _listening = true);

    // Silence Cue first and keep it silent: if a sentence starts between the
    // stop and the microphone opening, the recogniser transcribes Cue instead
    // of the user and acts on its own words.
    AudioBus.instance.mute();
    try {
      await AudioBus.instance.stop().timeout(const Duration(milliseconds: 400));
    } catch (_) {
      // A slow stop is not a reason to refuse to listen.
    }
    if (!mounted || token != _listenToken) return null;
    _showPreview();

    try {
      // A short tick confirms the press was felt, then the rising tone plays
      // only once the microphone is genuinely open. Playing it at key-down
      // tells the user to speak too early and swallows the first word.
      unawaited(Feedback.instance.gesture());

      VoiceCommandResult? result;
      for (var attempt = 0; attempt < 2; attempt++) {
        result = await VoiceCommandService.instance.listen(
          dictation: dictation,
          onReady: () {
            if (startedByKey && !_talkKeyHeld) {
              unawaited(VoiceCommandService.instance.finishListening());
            } else {
              unawaited(Feedback.instance.listening());
            }
          },
        );
        if (!mounted || token != _listenToken) return null;
        // Nothing was heard. If the key is still down, listen once more rather
        // than making the user perform the whole hold-and-speak ritual again.
        if (!startedByKey ||
            result.problem != VoiceProblem.noSpeech ||
            !_talkKeyHeld) {
          break;
        }
        unawaited(Feedback.instance.notHeard());
      }
      return result;
    } finally {
      // Every exit path must reopen the voice: a denied permission or a
      // cancelled listen would otherwise leave Cue silent for good. But an
      // attempt that has already been replaced must not touch the state of the
      // attempt that replaced it, or it would unmute the microphone's silence
      // guard and clear the new "Listening" state.
      if (token == _listenToken) {
        AudioBus.instance.unmute();
        if (mounted && _listening) {
          setState(() => _listening = false);
        }
      }
    }
  }

  Future<void> _runVoiceResult(VoiceCommandResult result) async {
    if (!mounted) return;
    if (result.problem != VoiceProblem.none) {
      unawaited(Feedback.instance.notHeard());
      await AudioBus.instance.say(
        _voiceProblemMessage(result.problem),
        priority: SpeechPriority.alert,
      );
      return;
    }
    if (FinderRequest.parse(result.words) case final request?) {
      unawaited(Feedback.instance.heard());
      await _runFinderRequest(request);
      return;
    }
    if (result.command == VoiceCommand.unknown) {
      unawaited(Feedback.instance.notHeard());
      await AudioBus.instance.say(
        _voiceProblemMessage(VoiceProblem.noMatch),
        priority: SpeechPriority.navigation,
      );
      return;
    }

    // A command was understood: one short high tick before it acts, so the
    // user knows the words landed even when the action itself is silent.
    unawaited(Feedback.instance.heard());

    switch (result.command) {
      case VoiceCommand.readNow:
        _activate();
      case VoiceCommand.repeat:
        _repeat();
      case VoiceCommand.stop:
        _stopSpeech();
      case VoiceCommand.pause:
        unawaited(_handlePause());
      case VoiceCommand.resume:
        unawaited(_handleResume());
      case VoiceCommand.nextSentence:
        unawaited(_nextSentence());
      case VoiceCommand.previousSentence:
        unawaited(_previousSentence());
      case VoiceCommand.startOver:
        unawaited(_startOver());
      case VoiceCommand.help:
        _help();
      case VoiceCommand.slower:
        unawaited(_changeSpeed(faster: false));
      case VoiceCommand.faster:
        unawaited(_changeSpeed(faster: true));
      case VoiceCommand.textMode:
        unawaited(_setInterpretation(Interpretation.text));
      case VoiceCommand.findKeys:
      case VoiceCommand.findPhone:
      case VoiceCommand.findGlasses:
      case VoiceCommand.findPen:
      case VoiceCommand.findBottle:
        _findItem(result.command.target!);
      case VoiceCommand.objectMode:
        unawaited(_setInterpretation(Interpretation.object));
      case VoiceCommand.banknoteMode:
        unawaited(_setInterpretation(Interpretation.banknote));
      case VoiceCommand.autoDescriptionsOn:
        _setAutoDescriptions(true);
      case VoiceCommand.autoDescriptionsOff:
        _setAutoDescriptions(false);
      case VoiceCommand.screenMode:
        unawaited(_setInterpretation(Interpretation.screen));
      case VoiceCommand.torchOn:
        unawaited(_torchFromVoice(true));
      case VoiceCommand.torchOff:
        unawaited(_torchFromVoice(false));
      case VoiceCommand.currentTime:
        unawaited(_sayTime());
      case VoiceCommand.currentDate:
        unawaited(_sayDate());
      case VoiceCommand.location:
        unawaited(_sayLocation());
      case VoiceCommand.locationSettings:
        unawaited(_openLocationSettings());
      case VoiceCommand.toggleLanguage:
        _toggleLanguage();
      case VoiceCommand.whichLanguage:
        unawaited(_sayLanguage());
      case VoiceCommand.whatMode:
        unawaited(_sayMode());
      case VoiceCommand.torchState:
        unawaited(_sayTorchState());
      case VoiceCommand.readingSpeed:
        unawaited(_saySpeed());
      case VoiceCommand.battery:
        unawaited(_sayBattery());
      case VoiceCommand.repeatAnswer:
        unawaited(_repeatAnswer());
      case VoiceCommand.neverMind:
        unawaited(_handleNeverMind());
      case VoiceCommand.readingProgress:
        unawaited(_sayReadingProgress());
      case VoiceCommand.questionColour:
        unawaited(_sayColourInView());
      case VoiceCommand.whatIsLeft:
        unawaited(_saySide(ObjectDirection.left));
      case VoiceCommand.whatIsRight:
        unawaited(_saySide(ObjectDirection.right));
      case VoiceCommand.whoAreYou:
        unawaited(
          AudioBus.instance.say(
            _strings.cueName,
            priority: SpeechPriority.answer,
          ),
        );
      case VoiceCommand.howAreYou:
        unawaited(
          AudioBus.instance.say(
            _strings.cueReady,
            priority: SpeechPriority.answer,
          ),
        );
      case VoiceCommand.thanks:
        unawaited(
          AudioBus.instance.say(
            _strings.cueWelcome,
            priority: SpeechPriority.navigation,
          ),
        );
      case VoiceCommand.greeting:
        unawaited(
          AudioBus.instance.say(
            _strings.cueGreeting,
            priority: SpeechPriority.navigation,
          ),
        );
      case VoiceCommand.whatIsThis:
        // Ask the camera again. Repeating the last sentence would describe
        // whatever was in view before the user moved the phone, which is the
        // one thing a "what is this?" question is not asking about.
        _activate();
      case VoiceCommand.showPreview:
        _showPreview();
        unawaited(
          AudioBus.instance.say(
            _strings.previewShown,
            priority: SpeechPriority.navigation,
          ),
        );
      case VoiceCommand.hindiMode:
        unawaited(_setLanguage(CueLanguage.hindi));
      case VoiceCommand.englishMode:
        unawaited(_setLanguage(CueLanguage.english));
      case VoiceCommand.unknown:
        break;
    }
  }

  String _voiceProblemMessage(VoiceProblem problem) {
    final hi = _language.isHindi;
    switch (problem) {
      case VoiceProblem.unavailable:
        return hi
            ? 'इस फ़ोन में आवाज़ कमांड उपलब्ध नहीं हैं। स्क्रीन के जेस्चर इस्तेमाल करें।'
            : 'Voice commands are not available on this phone. Use the '
                  'screen gestures instead.';
      case VoiceProblem.localeMissing:
        return hi
            ? 'इस फ़ोन में हिंदी भाषण पहचान नहीं है। अंग्रेज़ी में कमांड कहें, '
                  'या जेस्चर इस्तेमाल करें।'
            : 'This phone does not have an English speech recogniser. '
                  'Use the screen gestures instead.';
      case VoiceProblem.permissionDenied:
        return hi
            ? 'माइक्रोफ़ोन की अनुमति बंद है। सेटिंग, अनुमतियाँ, माइक्रोफ़ोन में जाकर क्यू को अनुमति दें।'
            : 'Microphone access is off. Open Settings, Permissions, '
                  'Microphone, and allow it for Cue.';
      case VoiceProblem.noSpeech:
        return hi ? 'आवाज़ नहीं सुनी।' : 'No speech heard.';
      case VoiceProblem.noMatch:
        return hi
            ? 'मैं समझा नहीं। मदद कहें।'
            : 'I did not understand. Say help for commands.';
      case VoiceProblem.busy:
        return hi ? 'पहले से सुन रहा हूँ।' : 'Already listening.';
      case VoiceProblem.error:
        return hi
            ? 'आवाज़ कमांड समस्या। फिर कोशिश करें।'
            : 'Voice command error. Try again.';
      case VoiceProblem.none:
        return '';
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_pointers.isEmpty) {
      _maxPointers = 1;
      _pointersDownAt = DateTime.now();
      _pointersMoved = false;
    }
    _pointers.add(event.pointer);
    _pointerOrigins[event.pointer] = event.position;
    if (_pointers.length > _maxPointers) _maxPointers = _pointers.length;
    if (_pointers.length > 2) _pointersMoved = true;
  }

  void _onPointerMove(PointerMoveEvent event) {
    // Compare each finger with its own starting point. Two fingers are
    // normally further apart than the movement threshold, so comparing the
    // second finger with the first finger's origin would cancel every tap.
    final origin = _pointerOrigins[event.pointer];
    if (origin != null && (event.position - origin).distance > 40) {
      _pointersMoved = true;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    _pointerOrigins.remove(event.pointer);
    if (_pointers.isNotEmpty) return;

    final started = _pointersDownAt;
    final twoFingerTap =
        _maxPointers == 2 &&
        !_pointersMoved &&
        started != null &&
        DateTime.now().difference(started) < const Duration(milliseconds: 450);
    _resetPointerTracking();

    if (twoFingerTap) unawaited(_listenForCommand());
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _pointerOrigins.remove(event.pointer);
    if (_pointers.isEmpty) _resetPointerTracking();
  }

  void _resetPointerTracking() {
    _pointers.clear();
    _pointerOrigins.clear();
    _maxPointers = 0;
    _pointersDownAt = null;
    _pointersMoved = false;
  }

  void _togglePause() {
    if (_phase == LivePhase.paused ||
        _phase == LivePhase.error ||
        AudioBus.instance.readingPaused) {
      unawaited(_handleResume());
    } else {
      unawaited(_handlePause());
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > 0) {
      _repeat();
    } else if (velocity < 0) {
      _stopSpeech();
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity == 0) return;
    unawaited(_changeInterpretation(forward: velocity > 0));
  }

  void _onResult(String text) {
    if (!mounted) return;
    setState(() => _lastResult = text);
    // A sighted helper looking at the phone sees what was just read.
    _showPreview();
  }

  String get _semanticsLabel {
    if (_listening) return _strings.semanticsListening;
    if (_pipeline.activeItemName case final name?) {
      return _strings.findingItem(name);
    }
    switch (_phase) {
      case LivePhase.starting:
        return _strings.semanticsStarting;
      case LivePhase.searching:
        return _strings.semanticsLive;
      case LivePhase.paused:
        return _strings.semanticsPaused;
      case LivePhase.error:
        return _strings.semanticsProblem(_error ?? '');
    }
  }

  String get _phaseLabel {
    switch (_phase) {
      case LivePhase.starting:
        return _strings.startingCamera;
      case LivePhase.searching:
        if (_pipeline.activeItemName case final name?) {
          return _strings.findingItem(name);
        }
        return AudioBus.instance.readingPaused
            ? _strings.readingPausedLabel
            : _strings.cueLooking;
      case LivePhase.paused:
        return _strings.pausedLabel;
      case LivePhase.error:
        return _strings.cameraProblem;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _source.controller;
    final showPreview =
        controller != null &&
        controller.value.isInitialized &&
        _phase == LivePhase.searching;
    final finding = _pipeline.isSearchingForItem;

    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: showPreview
          ? SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Align(
                alignment: Alignment.center,
                heightFactor: 1,
                child: FilledButton.icon(
                  onPressed: _listening
                      ? null
                      : finding
                      ? _stopSpeech
                      : _chooseItem,
                  icon: Icon(finding ? Icons.stop : Icons.search),
                  label: Text(
                    finding ? _strings.stopSearch : _strings.findItem,
                  ),
                ),
              ),
            )
          : null,
      body: Semantics(
        container: true,
        label: _semanticsLabel,
        hint: _pipeline.interpretation == Interpretation.object
            ? _strings.objectTapHint
            : _strings.semanticsHint,
        onTap: _activate,
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          CustomSemanticsAction(
            label: _pipeline.interpretation == Interpretation.object
                ? _strings.describeNow
                : _strings.actionReadNow,
          ): _activate,
          if (_pipeline.interpretation == Interpretation.object)
            CustomSemanticsAction(
              label: _strings.autoDescriptions(
                !_pipeline.automaticDescriptions,
              ),
            ): () =>
                _setAutoDescriptions(!_pipeline.automaticDescriptions),
          if (showPreview)
            CustomSemanticsAction(
              label: finding ? _strings.stopSearch : _strings.findItem,
            ): finding
                ? _stopSpeech
                : _chooseItem,
          CustomSemanticsAction(label: _strings.actionRepeat): _repeat,
          CustomSemanticsAction(label: _strings.actionStop): _stopSpeech,
          CustomSemanticsAction(label: _strings.actionPauseResume):
              _togglePause,
          CustomSemanticsAction(label: _strings.actionNext): _nextSentence,
          CustomSemanticsAction(label: _strings.actionPrevious):
              _previousSentence,
          CustomSemanticsAction(label: _strings.actionStartOver): _startOver,
          CustomSemanticsAction(label: _strings.actionHelp): _help,
          CustomSemanticsAction(label: _strings.actionPreview): _showPreview,
          CustomSemanticsAction(label: _strings.actionSlower): _slowerSpeech,
          CustomSemanticsAction(label: _strings.actionFaster): _fasterSpeech,
          CustomSemanticsAction(label: _strings.actionSpeakCommand):
              _listenForCommand,
          CustomSemanticsAction(label: _strings.actionChangeMode):
              _nextInterpretation,
          CustomSemanticsAction(label: _strings.actionLanguage):
              _toggleLanguage,
          CustomSemanticsAction(label: _strings.actionTime): () =>
              unawaited(_sayTime()),
          CustomSemanticsAction(label: _strings.actionDate): () =>
              unawaited(_sayDate()),
          CustomSemanticsAction(label: _strings.actionLocation): () =>
              unawaited(_sayLocation()),
          CustomSemanticsAction(label: _strings.actionBattery): () =>
              unawaited(_sayBattery()),
          CustomSemanticsAction(label: _strings.actionProgress): () =>
              unawaited(_sayReadingProgress()),
          CustomSemanticsAction(label: _strings.actionColour): () =>
              unawaited(_sayColourInView()),
          CustomSemanticsAction(label: _strings.actionLeft): () =>
              unawaited(_saySide(ObjectDirection.left)),
          CustomSemanticsAction(label: _strings.actionRight): () =>
              unawaited(_saySide(ObjectDirection.right)),
        },
        excludeSemantics: true,
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: _activate,
            onLongPress: _help,
            onVerticalDragEnd: _onVerticalDragEnd,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (showPreview)
                  AnimatedOpacity(
                    opacity: _previewOn ? 1 : 0,
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOut,
                    // When the preview is hidden the camera widget is removed
                    // from the tree instead of fading in place. A fading child
                    // stays mounted, and CameraPreview throws if it rebuilds
                    // after the controller has been disposed.
                    child: _previewOn && !_teaching
                        ? _preview(controller)
                        : const SizedBox.shrink(),
                  ),
                if (!_developerMode)
                  const IgnorePointer(
                    child: ColoredBox(color: Color(0x66000000)),
                  ),
                // The status panel stays visible even when the preview fades.
                // A blank black screen with no text looks broken to a sighted
                // helper; the phase label and last reading must always be
                // readable.
                Align(alignment: Alignment.bottomCenter, child: _statusPanel()),
                _developerControls(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _preview(CameraController controller) {
    final size = controller.value.previewSize;
    if (size == null) return const SizedBox.shrink();

    // The preview is a courtesy for sighted helpers. It is dimmed and never
    // required: every decision in the app is spoken or felt. It fades out
    // after a few seconds; the camera keeps running behind the black screen.
    // In developer mode, it stays fully bright and renders live bounding boxes.
    return Opacity(
      opacity: _developerMode ? 1.0 : 0.45,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.height,
            height: size.width,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                CameraPreview(controller),
                if (_developerMode &&
                    _pipeline.interpretation == Interpretation.object)
                  ValueListenableBuilder<List<DetectedObject>>(
                    valueListenable: _pipeline.detectedObjects,
                    builder: (context, objects, _) {
                      return CustomPaint(
                        size: Size(size.height, size.width),
                        painter: ObjectBoundingBoxesPainter(objects),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _developerControls() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              if (_developerMode &&
                  _pipeline.interpretation == Interpretation.object)
                ValueListenableBuilder<List<DetectedObject>>(
                  valueListenable: _pipeline.detectedObjects,
                  builder: (context, objects, _) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(200),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF00E676),
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        '${objects.length} LIVE CANDIDATE${objects.length == 1 ? '' : 'S'}',
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      ),
                    );
                  },
                )
              else
                const SizedBox.shrink(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _toggleDeveloperMode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _developerMode
                          ? const Color(0xFF00E676)
                          : Colors.black.withAlpha(180),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _developerMode
                            ? const Color(0xFF00E676)
                            : Colors.white54,
                        width: 1.5,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _developerMode
                              ? Icons.developer_mode
                              : Icons.bug_report,
                          size: 16,
                          color: _developerMode ? Colors.black : Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _developerMode ? 'DEV ON' : 'DEV MODE',
                          style: TextStyle(
                            color: _developerMode ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPanel() {
    return ExcludeSemantics(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0x00000000), Color(0xDD000000)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ValueListenableBuilder<bool>(
              valueListenable: AudioBus.instance.reading,
              builder: (context, reading, _) {
                return Text(
                  _listening
                      ? _strings.listeningLabel
                      : reading
                      ? _strings.readingLabel
                      : _phaseLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
            if (_listening) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _strings.listeningHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
            ] else if (defaultTargetPlatform == TargetPlatform.android) ...[
              const SizedBox(height: 6),
              Text(
                _strings.holdVolumeHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 15),
              ),
            ],
            if (_phase == LivePhase.paused ||
                AudioBus.instance.readingPaused) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _strings.resumeHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
            ],
            if (_phase == LivePhase.error && _error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
              const SizedBox(height: 12),
              Text(
                _strings.retryHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 20),
              ),
            ],
            if (!_listening && _lastResult.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              Text(
                _developerMode &&
                        _pipeline.interpretation == Interpretation.object
                    ? _strings.lastScan(_lastResult)
                    : _lastResult,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
