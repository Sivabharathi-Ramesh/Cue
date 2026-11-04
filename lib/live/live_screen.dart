import 'dart:async';

import 'package:camera/camera.dart';
// Flutter's Material library also defines a `Feedback` class (the haptic
// helper). Cue's own audio/haptic layer is the one this screen means.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Feedback;
import 'package:flutter/semantics.dart';

import '../core/audio_bus.dart';
import '../core/feedback.dart';
import '../core/keep_awake.dart';
import '../core/tts_service.dart';
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

  /// Whether the preview and the status panel are currently visible.
  ///
  /// The screen is for sighted helpers, not for the user. It shows itself for
  /// five seconds when a session starts and whenever a new reading lands, then
  /// fades to black: the camera keeps reading in the dark, which is better for
  /// privacy and for battery.
  bool _previewOn = true;
  Timer? _previewTimer;

  static const Duration _previewWindow = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pipeline = FramePipeline(onResult: _onResult);
    unawaited(Feedback.instance.init());
    // Load the OCR model while the camera opens, so the first frame does not
    // pay the model-start cost inside FR-03's two-second budget.
    unawaited(OcrService.instance.warmUp());
    unawaited(_start());

    // FR-04 / section 7: a soft tick every two seconds while searching.
    // Once a result has been read, the tick stops: an endless beep in the ear
    // is noise, and the aiming cues still speak up if the text is lost.
    _searchTick = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      if (_phase == LivePhase.searching &&
          _lastResult.isEmpty &&
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
    unawaited(KeepAwake.set(false));
    unawaited(AudioBus.instance.stop());
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

    final error = await _source.start(onFrame: _pipeline.handleFrame);

    if (!mounted || token != _startToken) {
      _starting = false;
      if (error == null) await _source.stop();
      return;
    }

    _starting = false;

    if (error != null) {
      setState(() {
        _phase = LivePhase.error;
        _error = error;
      });
      unawaited(Feedback.instance.error());
      unawaited(AudioBus.instance.say(error, priority: SpeechPriority.alert));
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
    await AudioBus.instance.say('Cue is looking. Point the camera at text.');
  }

  Future<void> _pause({bool announce = true}) async {
    _startToken++;
    _starting = false;
    _previewTimer?.cancel();
    _previewOn = false;

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
          'Paused. Double tap to resume.',
          priority: SpeechPriority.navigation,
        ),
      );
    }
  }

  /// The one activation gesture. With TalkBack on, a double-tap on the focused
  /// full-screen node arrives here as a semantic tap; without TalkBack, the
  /// GestureDetector's double-tap does the same thing.
  void _activate() {
    unawaited(Feedback.instance.gesture());

    if (_phase == LivePhase.paused || _phase == LivePhase.error) {
      _pausedByUser = false;
      unawaited(_start());
      return;
    }

    if (_phase == LivePhase.searching) {
      _pipeline.requestManualRead();
      _showPreview();
      if (_pipeline.interpretation == Interpretation.text &&
          !AudioBus.instance.speaking.value) {
        unawaited(
          AudioBus.instance.say('Reading now.', priority: SpeechPriority.info),
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
      AudioBus.instance.say(
        'Controls. Double tap to read now. Swipe left or right to change '
        'interpretation. Open the actions menu for repeat, stop, pause, help, '
        'show preview, and slower or faster speech.',
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
        faster ? 'This is the fastest speed.' : 'This is the slowest speed.',
        priority: SpeechPriority.navigation,
      );
      return;
    }

    await AudioBus.instance.say(
      faster
          ? 'Faster. This is the new reading speed.'
          : 'Slower. This is the new reading speed.',
      priority: SpeechPriority.navigation,
    );
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
    unawaited(Feedback.instance.gesture());
    await AudioBus.instance.stop();

    final current = _pipeline.interpretation;
    final next = forward ? current.next : current.previous;
    _pipeline.setInterpretation(next);
    AudioBus.instance.forgetLastResult();
    _showPreview();

    if (kDebugMode) {
      debugPrint('live: interpretation ${next.name}');
    }

    await AudioBus.instance.say(
      next == Interpretation.text
          ? 'Text mode. Point at printed text.'
          : '${next.label} mode is not built yet. Swipe to change mode.',
      priority: SpeechPriority.navigation,
    );
  }

  void _togglePause() {
    if (_phase == LivePhase.paused || _phase == LivePhase.error) {
      _pausedByUser = false;
      unawaited(_start());
    } else if (_phase == LivePhase.searching) {
      _pausedByUser = true;
      unawaited(_pause());
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
    switch (_phase) {
      case LivePhase.starting:
        return 'Cue. Starting camera.';
      case LivePhase.searching:
        return 'Cue. Live camera.';
      case LivePhase.paused:
        return 'Cue. Paused.';
      case LivePhase.error:
        return 'Cue. Camera problem. ${_error ?? ''}';
    }
  }

  String get _phaseLabel {
    switch (_phase) {
      case LivePhase.starting:
        return 'Starting camera';
      case LivePhase.searching:
        return 'Cue is looking';
      case LivePhase.paused:
        return 'Paused';
      case LivePhase.error:
        return 'Camera problem';
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
        hint:
            'Double tap to read now. Swipe sideways to change '
            'interpretation. Use the actions menu for repeat, stop, pause, '
            'help and speech speed.',
        onTap: _activate,
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          const CustomSemanticsAction(label: 'Read now'): _activate,
          const CustomSemanticsAction(label: 'Repeat last result'): _repeat,
          const CustomSemanticsAction(label: 'Stop speaking'): _stopSpeech,
          const CustomSemanticsAction(label: 'Pause or resume'): _togglePause,
          const CustomSemanticsAction(label: 'Help'): _help,
          const CustomSemanticsAction(label: 'Show preview'): _showPreview,
          const CustomSemanticsAction(label: 'Slower speech'): _slowerSpeech,
          const CustomSemanticsAction(label: 'Faster speech'): _fasterSpeech,
          const CustomSemanticsAction(label: 'Change interpretation'):
              _nextInterpretation,
        },
        excludeSemantics: true,
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
              const IgnorePointer(child: ColoredBox(color: Color(0x66000000))),
              Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedOpacity(
                  opacity: _previewOn ? 1 : 0,
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOut,
                  child: _statusPanel(),
                ),
              ),
            ],
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
                  reading ? 'Reading' : _phaseLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
            if (_phase == LivePhase.paused) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                'Double tap to resume',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 18),
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
              const Text(
                'Double tap to try again',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 20),
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
