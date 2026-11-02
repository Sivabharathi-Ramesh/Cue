import 'tts_service.dart';

/// How important a spoken message is.
/// Higher value wins when two things want to speak at once.
enum SpeechPriority { info, navigation, answer, alert }

/// A single queue for every sound the app makes.
///
/// The rule: one voice at a time. A warning is never interrupted by a
/// menu announcement, and two screens can never talk over each other.
class AudioBus {
  AudioBus._();

  static final AudioBus instance = AudioBus._();

  bool _speaking = false;
  SpeechPriority _current = SpeechPriority.info;

  Future<void> say(
    String text, {
    SpeechPriority priority = SpeechPriority.info,
  }) async {
    if (text.trim().isEmpty) return;

    // Something more urgent is already speaking: drop this one.
    if (_speaking && priority.index < _current.index) return;

    _speaking = true;
    _current = priority;
    try {
      await TtsService.instance.speak(text);
    } catch (_) {
      // Never let a speech failure crash a screen.
    } finally {
      _speaking = false;
      _current = SpeechPriority.info;
    }
  }

  Future<void> stop() async {
    _speaking = false;
    await TtsService.instance.stop();
  }
}
