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

  /// True only while a *reading* is being spoken.
  ///
  /// The screen shows "Reading" from this, not from [speaking]: "Cue is
  /// looking" and an aiming cue are speech too, but they are not readings, and
  /// a sighted helper must not be told the opposite of what is happening.
  final ValueNotifier<bool> reading = ValueNotifier<bool>(false);

  bool _speaking = false;
  SpeechPriority _current = SpeechPriority.info;
  int _utterance = 0;
  String? _lastResult;

  /// What the user actually heard as a reading: an uncertain result includes
  /// the doubt preamble so repeat repeats the truth, not just the guess.
  String? _lastSpoken;

  /// The last result, in its raw recognised form, available to callers that
  /// compare text for deduplication.
  String? get lastResult => _lastResult;

  bool get isSpeaking => _speaking;

  /// The words the user will hear for a reading at this confidence level.
  ///
  /// The doubt must be the first thing said: a blind user cannot scan the
  /// face of the reader for hesitation, and a late "maybe" does not undo a
  /// wrong sentence spoken first.
  static String labelReading(
    String text, {
    bool uncertain = false,
  }) {
    final clean = text.trim();
    return uncertain
        ? 'I am not sure. I think it says: $clean'
        : clean;
  }

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
  ///
  /// [uncertain] states the recogniser's doubt first, before any of the
  /// proposed words. The answer is still useful, but never presented as
  /// definite.
  bool speakResult(
    String text, {
    bool force = false,
    bool uncertain = false,
    SpeechPriority priority = SpeechPriority.answer,
  }) {
    final clean = text.trim();
    if (clean.isEmpty) return false;
    final spoken = labelReading(clean, uncertain: uncertain);

    if (!force) {
      if (_lastResult != null && newTokenRatio(_lastResult!, clean) < 0.35) {
        return false;
      }
      // An alert (camera failure, safety message) is never interrupted by a
      // routine reading.
      if (_speaking && _current.index > priority.index) return false;
    }

    _lastResult = clean;
    _lastSpoken = spoken;
    unawaited(_speak(spoken, priority));
    return true;
  }

  /// Re-speaks the last result, even if it has not changed.
  Future<void> repeatLast() async {
    final last = _lastSpoken;
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
    _lastSpoken = null;
  }

  Future<void> _speak(String text, SpeechPriority priority) async {
    final id = ++_utterance;
    _current = priority;
    _speaking = true;
    speaking.value = true;
    reading.value = priority == SpeechPriority.answer;

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
        reading.value = false;
      }
    }
  }

  Future<void> stop() async {
    _utterance++;
    _speaking = false;
    _current = SpeechPriority.info;
    speaking.value = false;
    reading.value = false;
    try {
      await TtsService.instance.stop();
    } catch (_) {
      // Stopping an idle engine is not an error worth reporting.
    }
  }
}
