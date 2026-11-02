import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // Android takes the camera away from a backgrounded app. Release it
      // now instead of holding a dead handle.
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

  Future<void> _capture() async {
    if (_busy || !_ready) return;

    final run = ++_runId;
    setState(() {
      _busy = true;
      _taken = 0;
      _lastText = '';
    });

    AudioBus.instance.say('Reading.');

    // A blind user has no way to tell "working" from "frozen". If the burst is
    // slower than expected, say so once instead of leaving silence.
    final watchdog = Timer(const Duration(seconds: 12), () {
      if (mounted && run == _runId) {
        AudioBus.instance.say('Still working. Please wait.');
      }
    });

    try {
      final frames = await _camera.burst(
        shots: 10,
        keep: 3,
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

      final ocrWatch = Stopwatch()..start();
      final text = await OcrService.instance.readFrame(frames.first);
      if (!mounted || run != _runId) return;

      final words = speakable(text);

      debugPrint(
        'read: ocr ${ocrWatch.elapsedMilliseconds}ms, '
        '${words.length} characters',
      );

      if (words.isEmpty) {
        AudioBus.instance.say(
          'I could not read any text. Move closer, hold still, and make sure '
          'the page is lit.',
          priority: SpeechPriority.alert,
        );
        return;
      }

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
      appBar: AppBar(title: const Text('Read')),
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
