import 'dart:async';

import 'package:camera/camera.dart';
// Flutter's Material library also defines a `Feedback` class (the haptic
// helper). Cue's own audio/haptic layer is the one this screen means.
import 'package:flutter/material.dart' hide Feedback;
import 'package:flutter/semantics.dart';

import '../core/audio_bus.dart';
import '../core/feedback.dart';
import '../vision/frame_source.dart';
import '../vision/ocr_service.dart';
import 'frame_pipeline.dart';

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
    WidgetsBinding.instance.removeObserver(this);
    _startToken++;
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
    final restarting =
        _phase == LivePhase.paused || _phase == LivePhase.error;

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

    unawaited(Feedback.instance.ready());
    unawaited(_announceReady(token));
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
      if (!AudioBus.instance.speaking.value) {
        unawaited(
          AudioBus.instance.say(
            'Reading now.',
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
      AudioBus.instance.say(
        'Controls. Double tap to read now. Open the actions menu for repeat, '
        'stop, pause and help.',
        priority: SpeechPriority.navigation,
      ),
    );
  }

  void _cycleInterpretation() {
    unawaited(Feedback.instance.gesture());
    unawaited(
      AudioBus.instance.say(
        'Text reading only in this build.',
        priority: SpeechPriority.info,
      ),
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

  void _onResult(String text) {
    if (!mounted) return;
    setState(() => _lastResult = text);
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
    final showPreview = controller != null &&
        controller.value.isInitialized &&
        _phase == LivePhase.searching;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Semantics(
        container: true,
        label: _semanticsLabel,
        hint: 'Double tap to read now. Use the actions menu for repeat, stop, '
            'pause and help.',
        onTap: _activate,
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          const CustomSemanticsAction(label: 'Read now'): _activate,
          const CustomSemanticsAction(label: 'Repeat last result'): _repeat,
          const CustomSemanticsAction(label: 'Stop speaking'): _stopSpeech,
          const CustomSemanticsAction(label: 'Pause or resume'): _togglePause,
          const CustomSemanticsAction(label: 'Help'): _help,
          const CustomSemanticsAction(label: 'Text only'): _cycleInterpretation,
        },
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: _activate,
          onLongPress: _help,
          onVerticalDragEnd: _onVerticalDragEnd,
          onHorizontalDragEnd: (_) => _cycleInterpretation(),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (showPreview) _preview(controller),
              const IgnorePointer(
                child: ColoredBox(color: Color(0x66000000)),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: _statusPanel(),
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
    // required: every decision in the app is spoken or felt.
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
              valueListenable: AudioBus.instance.speaking,
              builder: (context, speaking, _) {
                return Text(
                  speaking ? 'Reading' : _phaseLabel,
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
