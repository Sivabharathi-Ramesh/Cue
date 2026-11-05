import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The language Cue reads and listens in.
///
/// English is the default. Hindi changes three things together: the OCR
/// recogniser, the voice that reads the result, and the language the speech
/// recogniser expects for commands. Keeping them in one value stops the app
/// from reading Hindi text with an English voice, or listening for Hindi
/// commands while the camera looks for Latin letters.
enum CueLanguage { english, hindi }

extension CueLanguageInfo on CueLanguage {
  /// Locale name used by the speech-recognition plugin (`speech_to_text`).
  String get speechLocale => this == CueLanguage.hindi ? 'hi_IN' : 'en_IN';

  /// Locale name used by the text-to-speech engine (`flutter_tts`).
  String get ttsLocale => this == CueLanguage.hindi ? 'hi-IN' : 'en-IN';

  /// Short name for logs and announcements.
  String get label => this == CueLanguage.hindi ? 'Hindi' : 'English';

  bool get isHindi => this == CueLanguage.hindi;
}

/// Remembers the chosen language across launches.
class LanguageService {
  LanguageService._();

  static final LanguageService instance = LanguageService._();

  /// Observable so the live screen can react without polling.
  final ValueNotifier<CueLanguage> language = ValueNotifier<CueLanguage>(
    CueLanguage.english,
  );

  bool _loaded = false;

  /// Loads the saved language. Safe to call more than once.
  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (file == null || !await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return;
      final value = json['language'];
      if (value == 'hi') language.value = CueLanguage.hindi;
    } catch (_) {
      // A corrupt or unreadable file means English, not a crash.
    }
  }

  /// Changes the language and saves it.
  ///
  /// [persist] is only false for an automatic startup fallback: the voice
  /// failed, but the user's explicit Hindi choice must survive a restart.
  Future<void> set(CueLanguage value, {bool persist = true}) async {
    if (language.value != value) language.value = value;
    if (!persist) return;
    try {
      final file = await _file();
      if (file == null) return;
      await file.writeAsString(
        jsonEncode(<String, String>{
          'language': value == CueLanguage.hindi ? 'hi' : 'en',
        }),
      );
    } catch (_) {
      // Losing the preference is better than blocking the switch.
    }
  }

  Future<File?> _file() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/cue_language.json');
    } catch (_) {
      return null;
    }
  }
}
