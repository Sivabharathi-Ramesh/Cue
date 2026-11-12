import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import 'cue_language.dart';

/// One voice for the whole app.
///
/// Every screen must speak through this class, never through FlutterTts
/// directly, so that speech can be stopped, paced and prioritised.
///
/// The reading speed is a user setting, not a constant. A page read for
/// someone who cannot see it has to be followable by ear; a rate that feels
/// brisk with sight is a wall of sound without it. The default is therefore
/// well below the engine's normal pace, and the two live-screen actions
/// ("Slower speech" / "Faster speech") move it up and down without a menu.
class TtsService {
  TtsService._();

  static final TtsService instance = TtsService._();

  /// The slowest and fastest rates the app will use.
  ///
  /// On flutter_tts for Android, 0.5 is approximately the engine's normal pace.
  /// A rate of 0.45 provides natural, clear and articulate speech without
  /// dragging syllables or slurring words.
  static const double minRate = 0.28;
  static const double maxRate = 0.65;

  /// How far one "slower" or "faster" action moves the rate.
  static const double step = 0.05;

  /// What a page is read at until the user says otherwise.
  ///
  /// 0.45 on Android and 0.48 on iOS provide a crisp, articulate and
  /// easy-to-follow voice pace.
  static double get defaultRate => Platform.isIOS ? 0.48 : 0.45;

  final FlutterTts _tts = FlutterTts();

  bool _ready = false;
  Future<void>? _initialising;

  CueLanguage _language = CueLanguage.english;
  bool _languageApplied = false;
  String? _appliedLocale;

  /// Null until the platform has been asked whether it can list voices. Some
  /// engines return an empty list, and then trying the locale is better than
  /// refusing to speak at all.
  bool? _canListLanguages;

  double _rate = 0.0;

  /// The rate currently applied to the voice, on the flutter_tts scale.
  double get rate => _currentRate;

  double get _currentRate => _rate == 0.0 ? defaultRate : _rate;

  bool get atSlowest => _currentRate <= minRate + 0.001;
  bool get atFastest => _currentRate >= maxRate - 0.001;

  Future<void> _init() {
    return _initialising ??= _doInit();
  }

  Future<void> _doInit() async {
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
      _language = LanguageService.instance.language.value;
      _languageApplied = await _applyLanguage(_language);
      if (!_languageApplied) {
        // The saved language has no installed voice. Fall back to the voice
        // that is always present instead of letting an English engine try to
        // pronounce Devanagari. [prepareLanguage] reports the result so the
        // caller can save it and switch OCR and speech recognition to match.
        _language = CueLanguage.english;
        _languageApplied = await _applyLanguage(CueLanguage.english);
      }
    } catch (_) {
      // Some devices do not ship an Indian voice. Fall back silently.
      _language = CueLanguage.english;
      await _tryLocale('en-US');
    }

    // A saved speed survives restarts. The file is tiny and read once, before
    // the first sentence, so there is no audible delay later.
    _rate = await _loadRate() ?? defaultRate;
    await _applyRate();
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    _ready = true;
  }

  Future<void> _applyRate() async {
    await _tts.setSpeechRate(_currentRate);
  }

  /// The voice currently selected.
  CueLanguage get language => _language;

  /// False when the engine has no voice for the selected language.
  bool get languageAvailable => _languageApplied;

  /// The exact locale the engine accepted, for the debug log.
  String? get appliedLocale => _appliedLocale;

  /// Initialises the engine and returns the language it can actually speak.
  ///
  /// If the saved language is Hindi and this phone has no Hindi voice, the
  /// result is English. The caller must save that result so OCR and speech
  /// recognition use the same language as the voice; otherwise the first
  /// sentence would be Devanagari text read by an English engine.
  Future<CueLanguage> prepareLanguage() async {
    await _init();
    return _language;
  }

  /// Switches the reading voice.
  ///
  /// Returns false when the phone has no voice for [language]. The caller
  /// should then keep the old language rather than read Hindi text with an
  /// English voice, which would sound like nonsense to the user.
  Future<bool> setLanguage(CueLanguage language) async {
    await _init();
    if (language == _language && _languageApplied) return true;

    final applied = await _applyLanguage(language);
    if (!applied) return false;

    _language = language;
    _languageApplied = true;
    return true;
  }

  Future<bool> _applyLanguage(CueLanguage language) async {
    final candidates = language.isHindi
        ? const <String>['hi-IN', 'hi']
        : const <String>['en-IN', 'en-US'];

    for (final candidate in candidates) {
      if (!await _isAvailable(candidate)) continue;
      if (await _tryLocale(candidate)) {
        await _selectClearVoice(candidate);
        return true;
      }
    }

    if (!language.isHindi) {
      // Some engines claim not to list English but still speak it. For the
      // fallback language, trying is better than refusing.
      if (await _tryLocale('en-IN')) {
        await _selectClearVoice('en-IN');
        return true;
      }
      if (await _tryLocale('en-US')) {
        await _selectClearVoice('en-US');
        return true;
      }
    }
    return false;
  }

  /// Selects the highest quality, most articulate voice available for [locale].
  Future<void> _selectClearVoice(String locale) async {
    try {
      final voices = await _tts.getVoices;
      if (voices is! List || voices.isEmpty) return;

      final wanted = _normaliseLocale(locale);
      Map<dynamic, dynamic>? bestVoice;
      int bestScore = -1;

      for (final item in voices) {
        if (item is! Map) continue;
        final vLocale = item['locale']?.toString();
        final vName = item['name']?.toString() ?? '';
        if (vLocale == null) continue;

        final norm = _normaliseLocale(vLocale);
        if (norm != wanted &&
            !norm.startsWith('$wanted-') &&
            !wanted.startsWith('$norm-')) {
          continue;
        }

        var score = 10;
        final lowerName = vName.toLowerCase();
        if (lowerName.contains('natural') || lowerName.contains('neural')) {
          score += 50;
        }
        if (lowerName.contains('network') ||
            lowerName.contains('enhanced') ||
            lowerName.contains('premium')) {
          score += 30;
        }
        if (lowerName.contains('local') || lowerName.contains('high')) {
          score += 15;
        }
        if (lowerName.contains('low') || lowerName.contains('compact')) {
          score -= 10;
        }

        final quality = item['quality'];
        if (quality is int) {
          score += (quality ~/ 10);
        }

        if (score > bestScore) {
          bestScore = score;
          bestVoice = item;
        }
      }

      if (bestVoice != null) {
        final name = bestVoice['name']?.toString();
        final chosenLocale = bestVoice['locale']?.toString();
        if (name != null && chosenLocale != null) {
          await _tts.setVoice(<String, String>{
            'name': name,
            'locale': chosenLocale,
          });
        }
      }
    } catch (_) {
      // Voice selection is best-effort. If engine rejects setVoice, locale stays.
    }
  }

  Future<bool> _isAvailable(String locale) async {
    if (_canListLanguages == false) return true;

    try {
      final languages = await _tts.getLanguages;
      if (languages is! List || languages.isEmpty) {
        _canListLanguages = false;
        return true;
      }
      _canListLanguages = true;

      final wanted = _normaliseLocale(locale);
      for (final item in languages) {
        final id = item is Map ? item['locale']?.toString() : item?.toString();
        if (id == null) continue;
        final normalised = _normaliseLocale(id);
        if (normalised == wanted || normalised.startsWith('$wanted-')) {
          return true;
        }
      }
      return false;
    } catch (_) {
      _canListLanguages = false;
      return true;
    }
  }

  Future<bool> _tryLocale(String locale) async {
    try {
      await _tts.setLanguage(locale);
      _appliedLocale = locale;
      return true;
    } catch (_) {
      return false;
    }
  }

  String _normaliseLocale(String locale) =>
      locale.toLowerCase().replaceAll('_', '-');

  /// Moves the reading speed one step slower.
  ///
  /// Returns false when the voice is already at the slowest setting, so the
  /// caller can say so instead of playing the same speed again.
  Future<bool> slower() async {
    await _init();
    return setRate(_currentRate - step);
  }

  /// Moves the reading speed one step faster.
  ///
  /// Returns false when the voice is already at the fastest setting.
  Future<bool> faster() async {
    await _init();
    return setRate(_currentRate + step);
  }

  /// Applies [rate], clamped to the readable range, and saves it.
  ///
  /// Returns true when the rate actually changed.
  Future<bool> setRate(double rate) async {
    await _init();

    final clamped = rate.clamp(minRate, maxRate).toDouble();
    if ((clamped - _currentRate).abs() < 0.001) return false;

    _rate = clamped;
    await _applyRate();
    // Saving is never allowed to hold up speech.
    unawaited(_saveRate());
    return true;
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

  // --- Saved preference -----------------------------------------------------

  static const String _fileName = 'cue_speech.json';
  static const String _rateKey = 'rate';

  Future<File?> _prefsFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      // A platform without path_provider support still speaks; it just does
      // not remember the speed.
      return null;
    }
  }

  Future<double?> _loadRate() async {
    try {
      final file = await _prefsFile();
      if (file == null || !await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return null;
      final value = json[_rateKey];
      if (value is! num) return null;
      return value.toDouble().clamp(minRate, maxRate).toDouble();
    } catch (_) {
      // A corrupt or unreadable file must not stop the app from speaking.
      return null;
    }
  }

  Future<void> _saveRate() async {
    try {
      final file = await _prefsFile();
      if (file == null) return;
      await file.writeAsString(jsonEncode(<String, double>{_rateKey: _rate}));
    } catch (_) {
      // Losing a preference is better than crashing a reading session.
    }
  }
}
