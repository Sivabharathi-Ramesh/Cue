import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/audio_bus.dart';
import '../vision/camera_service.dart';
import '../vision/ocr_service.dart';
import '../widgets/big_button.dart';

/// Mode 1 - Read.
///
/// Point the phone at a page, press Capture. The phone takes ten photos,
/// keeps the sharpest three, reads the best one, and speaks it.
class ReadScreen extends StatefulWidget {
  const ReadScreen({super.key});

  @override
  State<ReadScreen> createState() => _ReadScreenState();
}

class _ReadScreenState extends State<ReadScreen> with WidgetsBindingObserver {
  final CameraService _camera = CameraService();

  bool _ready = false;
  bool _busy = false;
  String? _error;
  String _lastText = '';

  /// Bumped by [stop]. Any capture that finishes after that is discarded, so
  /// a stopped reading can never start speaking again a second later.
  int _runId = 0;

  /// How many photos of the burst have landed. Shown on screen for sighted
  /// helpers; the user hears speech instead.
  int _taken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AudioBus.instance.say(
      'Read mode. Point the phone at the page, then press Capture.',
    );
    _startCamera();

    // Load the OCR model now, while the user is aiming, so the first capture
    // does not pay a multi-second model start afterwards.
    unawaited(OcrService.instance.warmUp());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera.dispose();
    // The OCR model is deliberately left loaded for the life of the app: it
    // costs a few megabytes, and closing it would make the next visit to Read
    // pay the multi-second model start again.
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Android takes the camera away from a backgrounded app. Release it
      // now instead of holding a dead handle.
      //
      // Only paused, not inactive: inactive also fires for the permission
      // dialog and the notification shade, where the camera is still ours.
      // Releasing it there races the dialog and can leave two cameras opening.
      _camera.dispose();
      if (mounted) setState(() => _ready = false);
    } else if (state == AppLifecycleState.resumed && !_ready) {
      _startCamera();
    }
  }

  Future<void> _startCamera() async {
    setState(() {
      _ready = false;
      _error = null;
    });

    final problem = await _camera.open();
    if (!mounted) return;

    setState(() {
      _ready = problem == null;
      _error = problem;
    });

    if (problem != null) {
      AudioBus.instance.say(problem, priority: SpeechPriority.alert);
    }
  }

  /// Whether the user has toggled the torch on for low-light reading.
  ///
  /// A blind user cannot see screen brightness — a manual toggle they can
  /// find by touch is safer and more predictable than an auto-detect.
  bool _torchOn = false;

  void _toggleTorch() {
    setState(() => _torchOn = !_torchOn);
    AudioBus.instance.say(_torchOn ? 'Torch on.' : 'Torch off.');
    HapticFeedback.selectionClick();
  }

  Future<void> _capture() async {
    if (_busy || !_ready) return;

    // FIX 1 – Haptic confirmation so the user knows the button was pressed.
    HapticFeedback.heavyImpact();

    final run = ++_runId;
    setState(() {
      _busy = true;
      _taken = 0;
      _lastText = '';
    });

    AudioBus.instance.say('Reading.');

    // A blind user has no way to tell "working" from "frozen". If the burst is
    // slower than expected, say so once instead of leaving silence.
    final watchdog = Timer(const Duration(seconds: 8), () {
      if (mounted && run == _runId) {
        AudioBus.instance.say('Still working. Please wait.');
      }
    });

    try {
      final frames = await _camera.burst(
        shots: 10,
        keep: 3,
        // FIX 3 – Pass torch state set by the user via the AppBar toggle.
        torch: _torchOn,
        onProgress: (taken) {
          if (mounted && run == _runId) {
            setState(() => _taken = taken);
          }
        },
        isCancelled: () => run != _runId,
      );
      if (!mounted || run != _runId) return;

      if (frames.isEmpty) {
        AudioBus.instance.say(
          'I could not take a photo. Try again.',
          priority: SpeechPriority.alert,
        );
        return;
      }

      // FIX 2 – Try all kept frames, not just the sharpest one.
      // If the top frame has no readable text (glare, partial cover, etc.)
      // the next-sharpest frame often succeeds.
      final ocrWatch = Stopwatch()..start();

      // Confirm out loud that the photos were taken, so the wait for OCR is
      // not silence from a phone that might have frozen.
      AudioBus.instance.say('Got it. Reading now.');

      String words = '';
      for (final frame in frames) {
        if (run != _runId) return; // user pressed Stop mid-loop
        final raw = await OcrService.instance.readFrame(frame);
        words = speakable(raw);
        if (words.isNotEmpty) break; // found readable text — stop trying
      }
      if (!mounted || run != _runId) return;

      debugPrint(
        'read: ocr ${ocrWatch.elapsedMilliseconds}ms, '
        '${words.length} characters',
      );

      if (words.isEmpty) {
        // Second haptic — a short double-tap pattern signals failure.
        HapticFeedback.lightImpact();
        await Future.delayed(const Duration(milliseconds: 120));
        HapticFeedback.lightImpact();

        AudioBus.instance.say(
          'I could not read any text. Move closer, hold still, and make sure '
          'the page is lit.',
          priority: SpeechPriority.alert,
        );
        return;
      }

      // Long single vibration = success.
      HapticFeedback.mediumImpact();

      setState(() => _lastText = words);
      AudioBus.instance.say(words);
    } finally {
      watchdog.cancel();
      if (mounted && run == _runId) {
        setState(() => _busy = false);
      }
    }
  }

  void _stop() {
    _runId++;
    AudioBus.instance.stop();
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Read'),
        actions: [
          // Torch toggle — labelled for TalkBack so the blind user hears
          // "Torch off, button" or "Torch on, button".
          Semantics(
            button: true,
            label: _torchOn ? 'Torch on' : 'Torch off',
            hint: 'Double tap to toggle the flash for dark rooms',
            excludeSemantics: true,
            child: IconButton(
              icon: Icon(
                _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                color: _torchOn ? Colors.amber : null,
              ),
              tooltip: _torchOn ? 'Torch on' : 'Torch off',
              onPressed: _ready ? _toggleTorch : null,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(child: _buildPreviewArea()),
              if (_busy) ...[
                const SizedBox(height: 6),
                Text(
                  _taken == 0
                      ? 'Starting camera'
                      : _taken >= 10
                      ? 'Reading the page'
                      : '$_taken of 10 photos',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
              if (_lastText.isNotEmpty) _buildRecognisedText(),
              const SizedBox(height: 8),
              BigButton(
                label: _busy ? 'Stop' : 'Capture',
                icon: _busy ? Icons.stop : Icons.camera_alt,
                semanticHint: _busy
                    ? 'Stops reading'
                    : 'Takes ten photos and reads the sharpest one',
                onPressed: _busy ? _stop : _capture,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewArea() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography, size: 48),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 16),
              BigButton(
                label: 'Try again',
                icon: Icons.refresh,
                onPressed: _startCamera,
              ),
            ],
          ),
        ),
      );
    }

    if (!_ready) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Starting camera', style: TextStyle(fontSize: 20)),
          ],
        ),
      );
    }

    final controller = _camera.controller;
    if (controller == null) {
      return const Center(child: Text('Starting camera'));
    }

    return Center(child: CameraPreview(controller));
  }

  Widget _buildRecognisedText() {
    // Sighted helpers (and the examiner) can see what was read. The app never
    // depends on this; it is a courtesy, not the interface.
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 96),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        child: Text(
          _lastText,
          style: const TextStyle(fontSize: 14),
          maxLines: 20,
        ),
      ),
    );
  }
}
