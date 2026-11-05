import 'dart:async';

import 'package:camera/camera.dart';
// Flutter's Material library also defines a `Feedback` class (the haptic
// helper). Cue's own audio/haptic layer is the one this screen means.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Feedback;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../core/audio_bus.dart';
import '../core/cue_language.dart';
import '../core/cue_strings.dart';
import '../core/feedback.dart';
import '../core/keep_awake.dart';
import '../core/tts_service.dart';
import '../core/voice_command.dart';
import '../core/voice_command_service.dart';
import '../core/voice_intro.dart';
import '../vision/frame_source.dart';
import '../vision/ocr_service.dart';
import 'frame_pipeline.dart';
import 'scene_router.dart';

/// The five states from section 8 of the specification.
enum LivePhase { starting, searching, paused, error }

/// The whole app: one live camera, no menu, no capture button.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with WidgetsBindingObserver {
  final PhoneCameraFrameSource _source = PhoneCameraFrameSource();
  late final FramePipeline _pipeline;

  LivePhase _phase = LivePhase.starting;
  String? _error;
  String _lastResult = '';

  Timer? _searchTick;
  bool _starting = false;
  int _startToken = 0;
  bool _pausedByUser = false;

  /// Whether the "no Hindi voice" warning has already been spoken this session.
  ///
  /// Auto-detection retries every few seconds while a Hindi page is in view.
  /// Without this flag the same warning would interrupt the user repeatedly.
  bool _voiceMissingAnnounced = false;

  /// Whether press-to-talk is currently listening.
  bool _listening = false;

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
      onLanguageDetected: _onLanguageAutoDetected,
      language: language,
    );
    unawaited(Feedback.instance.init());
    _keyChannel.setMethodCallHandler(_onHardwareKey);
    unawaited(_prepareAndStart());

    // FR-04 / section 7: a soft tick every two seconds while searching.
    // Once a result has been read, the tick stops: an endless beep in the ear
    // is noise, and the aiming cues still speak up if the text is lost.
    _searchTick = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      if (_phase == LivePhase.searching &&
          _lastResult.isEmpty &&
          !_listening &&
          !AudioBus.instance.speaking.value) {
        unawaited(Feedback.instance.tick());
      }
    });
  }

  @override
  void dispose() {
    _searchTick?.cancel();
    _previewTimer?.cancel();
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
      if (_phase != LivePhase.paused) {
        _pausedByUser = false;
        unawaited(_pause(announce: false));
      }
    } else if (state == AppLifecycleState.resumed) {
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
  Future<void> _prepareAndStart() async {
    final voiceLanguage = await TtsService.instance.prepareLanguage();
    if (!mounted) return;

    if (voiceLanguage != LanguageService.instance.language.value) {
      // Session-only fallback. Persisting this would erase the user's saved
      // Hindi choice just because this launch had no Hindi voice.
      await LanguageService.instance.set(voiceLanguage, persist: false);
      _pipeline.setLanguage(voiceLanguage);
      setState(() {});
    }

    // Load the OCR model while the camera opens, so the first frame does not
    // pay the model-start cost inside FR-03's two-second budget.
    unawaited(OcrService.instance.warmUp(voiceLanguage));
    unawaited(_start());
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

    final startError = await _source.start(onFrame: _pipeline.handleFrame);

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
    setState(() {
      _phase = LivePhase.searching;
      if (restarting) {
        // A restarted session reads the page in view again; the caption must
        // not keep showing the previous session's reading.
        _lastResult = '';
        AudioBus.instance.forgetLastResult();
      }
    });

    // The display must not time out mid-page: a locked screen backgrounds the
    // app and the camera stops without a word.
    unawaited(KeepAwake.set(true));
    _showPreview();
    unawaited(Feedback.instance.ready());
    unawaited(_announceReady(token));
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
    _previewTimer = Timer(_previewWindow, () {
      if (!mounted) return;
      // Do not go dark in the middle of a reading: a sighted helper following
      // the caption gets the whole sentence, then the screen fades.
      if (AudioBus.instance.reading.value) {
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
    _previewOn = false;
    _cancelVoice();

    await KeepAwake.set(false);
    await AudioBus.instance.stop();
    await _source.stop();
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

  void _stopSpeech() {
    unawaited(Feedback.instance.gesture());
    unawaited(AudioBus.instance.stop());
  }

  void _help() {
    unawaited(Feedback.instance.gesture());
    unawaited(
      AudioBus.instance.say(_strings.help, priority: SpeechPriority.navigation),
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

    _pipeline.setInterpretation(next);
    AudioBus.instance.forgetLastResult();
    _showPreview();

    if (kDebugMode) {
      debugPrint('live: interpretation ${next.name}');
    }

    await AudioBus.instance.say(
      next == Interpretation.text
          ? _strings.textModeAnnouncement
          : _strings.notBuilt(_strings.modeName(next.label)),
      priority: SpeechPriority.navigation,
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

    _voiceMissingAnnounced = false;
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

  /// Called by the pipeline when the camera detects a different script.
  ///
  /// The pipeline awaits this before speaking, so the new voice is in place for
  /// the very first Hindi sentence. Returning false keeps the old script; that
  /// is what happens when the phone has no Hindi voice.
  Future<bool> _onLanguageAutoDetected(CueLanguage detected) async {
    if (detected == _language) return true;

    await AudioBus.instance.stop();
    final voiceReady = await TtsService.instance.setLanguage(detected);
    if (!voiceReady) {
      if (!_voiceMissingAnnounced) {
        _voiceMissingAnnounced = true;
        await AudioBus.instance.say(
          detected.isHindi
              ? _strings.hindiVoiceMissing
              : _strings.englishVoiceMissing,
          priority: SpeechPriority.alert,
        );
      }
      return false;
    }

    _voiceMissingAnnounced = false;
    // Say the announcement in the language the user was in, not the one Cue
    // is becoming. A Hindi sentence heard by a user who chose English is noise.
    final outgoing = CueStrings(LanguageService.instance.language.value);
    await LanguageService.instance.set(detected);
    AudioBus.instance.forgetLastResult();
    unawaited(OcrService.instance.warmUp(detected));
    if (mounted) setState(() {});

    unawaited(
      AudioBus.instance.say(
        detected.isHindi ? outgoing.hindiDetected : outgoing.englishDetected,
        priority: SpeechPriority.navigation,
      ),
    );
    return true;
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
    switch (call.method) {
      case 'talkStart':
        unawaited(_listenForCommand());
      case 'talkEnd':
        unawaited(VoiceCommandService.instance.finishListening());
    }
    return null;
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
    if (_listening) return;

    // Stop Cue's own voice first, then close the bus. The camera pipeline
    // keeps analysing while the microphone is open, and an aiming cue or the
    // next sentence must not be recorded as a command.
    await AudioBus.instance.stop();
    AudioBus.instance.mute();
    if (!mounted) {
      AudioBus.instance.unmute();
      return;
    }

    final token = ++_listenToken;
    setState(() => _listening = true);
    _showPreview();

    try {
      // The rising tone starts immediately. The short pause after it keeps the
      // microphone from capturing the tone itself.
      unawaited(Feedback.instance.listening());
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted || token != _listenToken) return;

      final result = await VoiceCommandService.instance.listen();
      if (!mounted || token != _listenToken) return;

      setState(() => _listening = false);
      AudioBus.instance.unmute();
      await _runVoiceResult(result);
      await _sayReadingPausedHint();
    } finally {
      // Every exit path must reopen the voice: a denied permission or a
      // cancelled listen would otherwise leave Cue silent for good.
      AudioBus.instance.unmute();
      if (mounted && _listening) {
        setState(() => _listening = false);
      }
    }
  }

  Future<void> _runVoiceResult(VoiceCommandResult result) async {
    if (result.problem != VoiceProblem.none) {
      unawaited(Feedback.instance.notHeard());
      await AudioBus.instance.say(
        _voiceProblemMessage(result.problem),
        priority: SpeechPriority.alert,
      );
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
      case VoiceCommand.objectMode:
        unawaited(_setInterpretation(Interpretation.object));
      case VoiceCommand.banknoteMode:
        unawaited(_setInterpretation(Interpretation.banknote));
      case VoiceCommand.screenMode:
        unawaited(_setInterpretation(Interpretation.screen));
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
        return hi
            ? 'मुझे कुछ सुनाई नहीं दिया। वॉल्यूम डाउन दबाए रखकर फिर कोशिश करें।'
            : 'I did not hear anything. Hold volume down and try again.';
      case VoiceProblem.noMatch:
        return hi
            ? 'मैं समझा नहीं। पढ़ो, दोहराओ, रुको, ठहरो, जारी रखो, अगला, पिछला, मदद, धीरे, तेज़, या मोड कहें।'
            : 'I did not understand. Say read, repeat, stop, pause, resume, '
                  'next, back, help, slower, faster, or a mode.';
      case VoiceProblem.busy:
        return hi ? 'पहले से सुन रहा हूँ।' : 'Already listening.';
      case VoiceProblem.error:
        return hi
            ? 'आवाज़ कमांड में समस्या आई। फिर कोशिश करें, या स्क्रीन के जेस्चर इस्तेमाल करें।'
            : 'Voice commands hit a problem. Try again, or use the screen '
                  'gestures.';
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: Semantics(
        container: true,
        label: _semanticsLabel,
        hint: _strings.semanticsHint,
        onTap: _activate,
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          CustomSemanticsAction(label: _strings.actionReadNow): _activate,
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
                    child: _preview(controller),
                  ),
                const IgnorePointer(
                  child: ColoredBox(color: Color(0x66000000)),
                ),
                // The status panel stays visible even when the preview fades.
                // A blank black screen with no text looks broken to a sighted
                // helper; the phase label and last reading must always be
                // readable.
                Align(alignment: Alignment.bottomCenter, child: _statusPanel()),
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
    return Opacity(
      opacity: 0.45,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.height,
            height: size.width,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  Widget _statusPanel() {
    return ExcludeSemantics(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
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
            if (_lastResult.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              Text(
                _lastResult,
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
