import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cue_language.dart';
import 'cue_strings.dart';
import 'sentence_splitter.dart';
import 'text_similarity.dart';
import 'tts_service.dart';

/// How important a spoken message is.
/// Higher value wins when two things want to speak at once.
enum SpeechPriority { info, navigation, answer, alert }

/// What a sentence-navigation request did.
enum ReadingMove {
  /// The queue moved and playback restarted at the new sentence.
  moved,

  /// The queue is already at its first sentence.
  atStart,

  /// The queue is already at its last sentence.
  atEnd,

  /// Nothing has been read yet, or the last reading was cleared.
  noReading,
}

/// A single queue for every sound the app makes.
///
/// The rule: one voice at a time. A warning is never interrupted by a menu
/// announcement, and two screens can never talk over each other.
///
/// A reading is kept as a list of sentences rather than one long utterance.
/// That is what makes "next", "back", "repeat" and "start over" possible, and
/// it fixes the old behaviour where pausing stopped the camera instead of the
/// reading.
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

  /// The sentences of the current reading, in order.
  List<String> _sentences = const <String>[];

  /// The sentence being spoken, or the last one spoken after a pause.
  int _index = 0;

  /// Bumped whenever playback must stop. An old playback loop checks this
  /// before advancing, so a pause or a jump can never be overtaken by the loop
  /// it interrupted.
  int _playToken = 0;

  bool _readingActive = false;
  bool _readingPaused = false;
  bool _sessionUncertain = false;
  SpeechPriority _sessionPriority = SpeechPriority.answer;

  /// Set to false every time a reading is parked, so a hint may be spoken once.
  bool _pauseHintShown = true;

  /// Completes when the current utterance is interrupted. Lets the playback
  /// loop wake up instead of waiting for a speech engine that may never
  /// return its Future.
  Completer<void>? _utteranceCancel;

  /// True while the microphone is open for a voice command.
  ///
  /// Nothing Cue says may reach the recogniser. Without this, an aiming cue or
  /// the next sentence of a reading would be picked up as if the user had
  /// spoken it.
  bool _muted = false;

  bool get isMuted => _muted;

  /// The last result, in its raw recognised form, available to callers that
  /// compare text for deduplication.
  String? get lastResult => _lastResult;

  bool get isSpeaking => _speaking;

  /// Whether a reading queue exists and has not finished.
  bool get hasReading => _readingActive && _sentences.isNotEmpty;

  /// Whether a reading queue exists and is currently stopped mid-page.
  bool get readingPaused => _readingPaused && _sentences.isNotEmpty;

  /// The sentence the next "resume" or "repeat" will speak, zero-based.
  int get sentenceIndex => _index;

  /// How many sentences the current reading has.
  int get sentenceCount => _sentences.length;

  /// The words the user will hear for a reading at this confidence level.
  ///
  /// The doubt must be the first thing said: a blind user cannot scan the
  /// face of the reader for hesitation, and a late "maybe" does not undo a
  /// wrong sentence spoken first.
  static String labelReading(String text, {bool uncertain = false}) {
    final clean = text.trim();
    if (!uncertain) return clean;
    final prefix = LanguageService.instance.language.value.isHindi
        ? 'मुझे यकीन नहीं है। मुझे लगता है यह लिखा है: '
        : 'I am not sure. I think it says: ';
    return '$prefix$clean';
  }

  Future<void> say(
    String text, {
    SpeechPriority priority = SpeechPriority.info,
  }) async {
    if (_muted) return;
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
    if (_muted) return false;
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

    final sentences = splitSentences(clean);
    if (sentences.isEmpty) return false;

    _lastResult = clean;
    _lastSpoken = labelReading(clean, uncertain: uncertain);
    _startReading(sentences, uncertain: uncertain, priority: priority);
    return true;
  }

  /// Re-speaks the current sentence, or the last result if no queue remains.
  Future<void> repeatLast() async {
    final move = await repeatSentence();
    if (move != ReadingMove.noReading) return;

    final last = _lastSpoken;
    if (last == null) {
      await say(
        CueStrings(LanguageService.instance.language.value).nothingToRepeat,
        priority: SpeechPriority.info,
      );
      return;
    }
    await _speak(last, SpeechPriority.answer);
  }

  /// Moves to the next sentence and reads from there.
  Future<ReadingMove> nextSentence() async {
    if (_sentences.isEmpty) return ReadingMove.noReading;
    if (_index >= _sentences.length - 1) return ReadingMove.atEnd;
    await _jumpTo(_index + 1, keepPaused: _readingPaused);
    return ReadingMove.moved;
  }

  /// Moves to the previous sentence and reads from there.
  Future<ReadingMove> previousSentence() async {
    if (_sentences.isEmpty) return ReadingMove.noReading;
    if (_index <= 0) return ReadingMove.atStart;
    await _jumpTo(_index - 1, keepPaused: _readingPaused);
    return ReadingMove.moved;
  }

  /// Returns to the first sentence and reads from there.
  Future<ReadingMove> startOver() async {
    if (_sentences.isEmpty) return ReadingMove.noReading;
    await _jumpTo(0, keepPaused: _readingPaused);
    return ReadingMove.moved;
  }

  /// Repeats the current sentence.
  ///
  /// While a reading is playing, the loop continues from here. While it is
  /// paused, just this sentence is spoken and the page stays paused.
  Future<ReadingMove> repeatSentence() async {
    if (_sentences.isEmpty) return ReadingMove.noReading;
    await _jumpTo(_index, keepPaused: _readingPaused);
    return ReadingMove.moved;
  }

  /// Stops the reading where it is, keeping the queue for [resumeReading].
  ///
  /// Returns false when there is no reading to pause, so the caller can fall
  /// back to pausing the camera.
  Future<bool> pauseReading() async {
    if (!_readingActive || _sentences.isEmpty) return false;
    if (_readingPaused && !_speaking) return true;

    _playToken++;
    _readingPaused = true;
    _pauseHintShown = false;
    await _cancelSpeech();
    return true;
  }

  /// Continues a paused reading from the sentence that was interrupted.
  ///
  /// Returns false when there is no paused reading, so the caller can fall
  /// back to resuming the camera.
  Future<bool> resumeReading() async {
    if (!_readingActive || _sentences.isEmpty || !_readingPaused) {
      return false;
    }

    _readingPaused = false;
    final token = ++_playToken;
    unawaited(_play(token));
    return true;
  }

  /// Forgets what was last read without speaking.
  ///
  /// Called when a reading session restarts after a pause. Returning to the app
  /// is a deliberate act, so the page in view is read once again instead of
  /// being swallowed by the "already spoken" rule.
  void forgetLastResult() {
    _lastResult = null;
    _lastSpoken = null;
    _sentences = const <String>[];
    _index = 0;
    _readingActive = false;
    _readingPaused = false;
    _playToken++;
  }

  void _startReading(
    List<String> sentences, {
    required bool uncertain,
    required SpeechPriority priority,
  }) {
    _sentences = List<String>.unmodifiable(sentences);
    _index = 0;
    _sessionUncertain = uncertain;
    _sessionPriority = priority;
    _readingActive = true;
    _readingPaused = false;
    _pauseHintShown = true;
    final token = ++_playToken;
    unawaited(_play(token));
  }

  Future<void> _play(int token) async {
    while (token == _playToken && _index < _sentences.length) {
      if (_readingPaused) return;

      final completed = await _speak(_speechFor(_index), _sessionPriority);

      if (token != _playToken) return;

      if (!completed) {
        // An alert took the voice, or speech failed. Keep the queue where it
        // is so "resume" can continue after the interruption.
        _readingPaused = true;
        _pauseHintShown = false;
        reading.value = false;
        if (token == _playToken) unawaited(_hintAfterInterruption(token));
        return;
      }

      if (_index >= _sentences.length - 1) {
        _readingActive = false;
        _readingPaused = false;
        reading.value = false;
        return;
      }

      _index++;
    }
  }

  /// Waits for an interrupting message to finish, then says the page is paused.
  ///
  /// An interrupting alert is allowed to win the voice. It is not allowed to
  /// leave a blind user in silence with no way to find out why the page
  /// stopped.
  Future<void> _hintAfterInterruption(int token) async {
    for (var i = 0; i < 60 && _speaking; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (token != _playToken || !_readingPaused || _muted) return;
    if (!takeReadingPauseHint()) return;
    await say(
      CueStrings(LanguageService.instance.language.value).readingPaused,
      priority: SpeechPriority.navigation,
    );
  }

  /// Consumes the one-shot "reading paused" hint for this pause.
  ///
  /// The live screen calls this after an action that stops the voice, so the
  /// user is told the page can be resumed instead of hearing an abrupt stop.
  bool takeReadingPauseHint() {
    if (!_readingPaused || _pauseHintShown) return false;
    _pauseHintShown = true;
    return true;
  }

  String _speechFor(int index) {
    final sentence = _sentences[index];
    if (index == 0 && _sessionUncertain) {
      return labelReading(sentence, uncertain: true);
    }
    return sentence;
  }

  Future<void> _jumpTo(int index, {bool keepPaused = false}) async {
    final target = index.clamp(0, _sentences.length - 1);
    _index = target;
    _readingActive = true;
    _readingPaused = keepPaused;
    final token = ++_playToken;
    await _cancelSpeech();
    if (token != _playToken) return;
    if (keepPaused) {
      unawaited(_playOne(token));
    } else {
      unawaited(_play(token));
    }
  }

  /// Speaks exactly one sentence and parks the queue again.
  ///
  /// Navigation commands issued while paused must not silently restart the
  /// whole page. The user asked to hear another sentence, not to lose the
  /// pause.
  Future<void> _playOne(int token) async {
    await _speak(_speechFor(_index), _sessionPriority);
    if (token != _playToken) return;
    _readingPaused = true;
    _pauseHintShown = true;
    reading.value = false;
  }

  Future<bool> _speak(String text, SpeechPriority priority) async {
    if (_muted) return false;
    final id = ++_utterance;
    _current = priority;
    _speaking = true;
    speaking.value = true;
    if (priority == SpeechPriority.answer) reading.value = true;

    try {
      final cancel = Completer<void>();
      _utteranceCancel = cancel;
      // An interruption completes `cancel` before the engine has finished
      // (or ever returns — iOS can drop the callback silently). Either way
      // the caller is awake immediately and can park the queue.
      await Future.any(<Future<void>>[
        TtsService.instance.speak(text),
        cancel.future,
      ]);
      if (identical(_utteranceCancel, cancel)) _utteranceCancel = null;
      // A newer utterance or a cancel superseded this one.
      return id == _utterance;
    } catch (_) {
      // Never let a speech failure crash a screen.
      return false;
    } finally {
      // Only the most recent utterance may clear the flag. An older, stopped
      // utterance finishing late must not unlock the bus while a newer one is
      // still talking.
      if (id == _utterance) {
        _speaking = false;
        _current = SpeechPriority.info;
        speaking.value = false;
        if (priority == SpeechPriority.answer) reading.value = false;
      }
    }
  }

  Future<void> _cancelSpeech() async {
    _utterance++;
    final cancel = _utteranceCancel;
    _utteranceCancel = null;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
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

  Future<void> stop() async {
    _playToken++;
    if (_readingActive && _sentences.isNotEmpty) {
      _readingPaused = true;
      _pauseHintShown = false;
    }
    await _cancelSpeech();
  }

  /// Silences the bus while a voice command is being recorded.
  ///
  /// The microphone must not hear Cue's own voice. The caller still calls
  /// [stop] first so whatever was being said ends before the mic opens.
  void mute() {
    _muted = true;
  }

  /// Lets Cue speak again after a listen, including after a failed one.
  void unmute() {
    _muted = false;
  }
}
