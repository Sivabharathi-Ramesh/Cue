import 'dart:io' show Platform;

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

    if (Platform.isIOS) {
      // Two iOS-only settings, and both matter for this app.
      //
      // 1. setSharedInstance(true) lets flutter_tts own the audio session
      //    instead of borrowing it, so speech survives the screen locking.
      //
      // 2. The 'playback' category keeps speech audible when the Ring/Silent
      //    switch is set to silent. Without it, an iPhone with that switch
      //    flipped makes the whole app look broken: no error, no sound.
      await _tts.setSharedInstance(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        <IosTextToSpeechAudioCategoryOptions>[
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
    }

    try {
      await _tts.setLanguage('en-IN');
    } catch (_) {
      // Some devices do not ship an Indian English voice. Fall back silently.
      await _tts.setLanguage('en-US');
    }

    // iOS and Android use different speech-rate scales. 0.45 on Android is
    // noticeably slower than 0.45 on iOS, so each platform gets its own value.
    await _tts.setSpeechRate(Platform.isIOS ? 0.52 : 0.45);
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
