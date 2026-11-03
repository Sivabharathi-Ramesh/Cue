import 'dart:async';

import 'package:flutter/foundation.dart';

import 'text_similarity.dart';
import 'tts_service.dart';

/// How important a spoken message is.
/// Higher value wins when two things want to speak at once.
enum SpeechPriority { info, navigation, answer, alert }

/// A single queue for every sound the app makes.
///
/// The rule: one voice at a time. A warning is never interrupted by a menu
/// announcement, and two screens can never talk over each other.
class AudioBus {
  AudioBus._();

  static final AudioBus instance = AudioBus._();

  /// Observable speaking state, so the live screen can show "Reading" without
  /// polling or guessing.
  final ValueNotifier<bool> speaking = ValueNotifier<bool>(false);

  bool _speaking = false;
  SpeechPriority _current = SpeechPriority.info;
  int _utterance = 0;
  String? _lastResult;

  /// The last result spoken as a reading, available to the repeat gesture.
  String? get lastResult => _lastResult;

  bool get isSpeaking => _speaking;

  Future<void> say(
    String text, {
    SpeechPriority priority = SpeechPriority.info,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return;

    // Something more urgent is already speaking: drop this one.
    if (_speaking && priority.index < _current.index) return;

    await _speak(clean, priority);
  }

  /// Speaks an OCR result only if it contains enough new material.
  ///
  /// Returns true when speech started. The call does not wait for speech to
  /// finish: the camera pipeline must keep analysing while the user listens.
  ///
  /// [force] is used by the manual read gesture: the user asked for this page
  /// again, so deduplication must not swallow it.
  bool speakResult(
    String text, {
    bool force = false,
    SpeechPriority priority = SpeechPriority.answer,
  }) {
    final clean = text.trim();
    if (clean.isEmpty) return false;

    if (!force) {
      if (_lastResult != null && newTokenRatio(_lastResult!, clean) < 0.35) {
        return false;
      }
      // An alert (camera failure, safety message) is never interrupted by a
      // routine reading.
      if (_speaking && _current.index > priority.index) return false;
    }

    _lastResult = clean;
    unawaited(_speak(clean, priority));
    return true;
  }

  /// Re-speaks the last result, even if it has not changed.
  Future<void> repeatLast() async {
    final last = _lastResult;
    if (last == null) {
      await say('Nothing to repeat yet.', priority: SpeechPriority.info);
      return;
    }
    await _speak(last, SpeechPriority.answer);
  }

  /// Forgets what was last read without speaking.
  ///
  /// Called when a reading session restarts after a pause. Returning to the app
  /// is a deliberate act, so the page in view is read once again instead of
  /// being swallowed by the "already spoken" rule.
  void forgetLastResult() {
    _lastResult = null;
  }

  Future<void> _speak(String text, SpeechPriority priority) async {
    final id = ++_utterance;
    _current = priority;
    _speaking = true;
    speaking.value = true;

    try {
      await TtsService.instance.speak(text);
    } catch (_) {
      // Never let a speech failure crash a screen.
    } finally {
      // Only the most recent utterance may clear the flag. An older, stopped
      // utterance finishing late must not unlock the bus while a newer one is
      // still talking.
      if (id == _utterance) {
        _speaking = false;
        _current = SpeechPriority.info;
        speaking.value = false;
      }
    }
  }

  Future<void> stop() async {
    _utterance++;
    _speaking = false;
    _current = SpeechPriority.info;
    speaking.value = false;
    try {
      await TtsService.instance.stop();
    } catch (_) {
      // Stopping an idle engine is not an error worth reporting.
    }
  }
}
