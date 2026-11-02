import 'package:flutter_tts/flutter_tts.dart';

/// One voice for the whole app.
///
/// Every screen must speak through this class, never through FlutterTts
/// directly, so that speech can be stopped, paced and (later) prioritised.
class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();

  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    try {
      await _tts.setLanguage('en-IN');
    } catch (_) {
      // Some devices do not ship an Indian English voice. Fall back silently.
      await _tts.setLanguage('en-US');
    }
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    _ready = true;
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _init();
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
