import 'dart:async';

import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'cue_language.dart';
import 'voice_command.dart';

/// Why a voice command attempt produced no command.
enum VoiceProblem {
  /// A command was recognised.
  none,

  /// The phone has no usable speech recogniser.
  unavailable,

  /// The phone has a recogniser, but not one for the chosen language.
  localeMissing,

  /// Microphone or speech-recognition permission was refused.
  permissionDenied,

  /// The microphone heard nothing before the timeout.
  noSpeech,

  /// Words were heard, but none of them is a Cue command.
  noMatch,

  /// Another listen is already running.
  busy,

  /// The platform recogniser failed for another reason.
  error,
}

class VoiceCommandResult {
  const VoiceCommandResult(
    this.command, {
    this.words = '',
    this.problem = VoiceProblem.none,
  });

  final VoiceCommand command;

  /// What the recogniser actually heard, for the debug log.
  final String words;

  final VoiceProblem problem;

  bool get ok =>
      problem == VoiceProblem.none && command != VoiceCommand.unknown;
}

/// Press-to-talk voice commands.
///
/// Cue does not listen continuously. The live screen starts one short listen
/// when the user asks for it, and this class stops as soon as a command is
/// recognised. Audio is handed to the phone's own speech recogniser; Cue never
/// stores it.
///
/// The recogniser may use an online service on phones without an offline
/// English model. Reading itself remains fully on-device; voice commands are an
/// optional input method.
class VoiceCommandService {
  VoiceCommandService._();

  static final VoiceCommandService instance = VoiceCommandService._();

  /// Short phrases that bias Android 13+ recognition towards Cue's vocabulary.
  static const List<String> _phrases = <String>[
    'read',
    'read now',
    'read this page',
    'repeat',
    'say again',
    'stop',
    'stop reading',
    'pause',
    'resume',
    'next',
    'back',
    'start over',
    'help',
    'what can I say',
    'slower',
    'faster',
    'text mode',
    'object mode',
    'banknote mode',
    'screen mode',
    'show preview',
    'hindi',
    'english',
  ];

  /// The same bias for a Hindi listen.
  static const List<String> _phrasesHindi = <String>[
    'पढ़ो',
    'पढ़िए',
    'अगला',
    'पिछला',
    'दोहराओ',
    'फिर से',
    'शुरू से',
    'रुको',
    'ठहरो',
    'जारी रखो',
    'मदद',
    'धीरे',
    'तेज़',
    'पाठ मोड',
    'हिंदी',
    'अंग्रेज़ी',
    'दिखाओ',
  ];

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;
  bool _available = false;
  bool _listening = false;
  bool _permissionError = false;
  bool _localeMissing = false;
  String? _localeId;
  Completer<VoiceCommandResult>? _pending;

  /// The language the current recogniser session is configured for.
  CueLanguage _language = CueLanguage.english;

  /// Set when the user switches language; the locale is looked up again before
  /// the next listen.
  bool _localeDirty = true;

  /// Bumped for each listen so a timer from an old listen cannot finish a new
  /// one.
  int _session = 0;

  /// True while the user has let go of the talk key and the platform is being
  /// stopped on purpose. Errors during that window are expected, not failures.
  bool _stopping = false;

  /// The last words the recogniser reported, used when the user releases the
  /// talk key before the platform sends a final result.
  String _lastWords = '';

  bool get isListening => _listening;

  /// Starts one listen and waits for a command, a timeout or an error.
  ///
  /// The caller should stop any speech first: otherwise the microphone hears
  /// Cue's own voice.
  Future<VoiceCommandResult> listen() async {
    if (_listening) {
      return const VoiceCommandResult(
        VoiceCommand.unknown,
        problem: VoiceProblem.busy,
      );
    }

    final ready = await _ensureReady();
    if (!ready) {
      return VoiceCommandResult(
        VoiceCommand.unknown,
        problem: _permissionError
            ? VoiceProblem.permissionDenied
            : _localeMissing
            ? VoiceProblem.localeMissing
            : VoiceProblem.unavailable,
      );
    }

    try {
      if (_speech.isListening) await _speech.cancel();
    } catch (_) {
      // An idle recogniser is not an error.
    }

    _listening = true;
    _stopping = false;
    _lastWords = '';
    final session = ++_session;
    final completer = Completer<VoiceCommandResult>();
    _pending = completer;

    try {
      await _speech.listen(
        onResult: (result) => _onResult(session, result),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.confirmation,
          // Two seconds of silence ends the command. Seven seconds is the
          // longest a single press-to-talk attempt may last.
          pauseFor: const Duration(seconds: 2),
          listenFor: const Duration(seconds: 7),
          localeId: _localeId,
          contextualPhrases: _phrasesFor(_language),
        ),
      );
    } catch (error) {
      if (kDebugMode) debugPrint('voice: listen failed $error');
      _finish(
        const VoiceCommandResult(
          VoiceCommand.unknown,
          problem: VoiceProblem.error,
        ),
      );
      return completer.future;
    }

    // Safety net: a platform that never sends a final result must not leave
    // the live screen stuck in "Listening".
    Timer(const Duration(seconds: 8), () {
      if (!_listening || session != _session) return;
      unawaited(_speech.stop().catchError((_) {}));
      _finish(
        const VoiceCommandResult(
          VoiceCommand.unknown,
          problem: VoiceProblem.noSpeech,
        ),
      );
    });

    return completer.future;
  }

  /// Ends the current listen when the user lets go of the talk key.
  ///
  /// The platform is given a moment to deliver its own final result. If it
  /// does not, the last partial transcript is used, so a quick "read" is not
  /// thrown away just because the key came up early.
  Future<void> finishListening() async {
    if (!_listening) return;
    final session = _session;
    _stopping = true;

    try {
      await _speech.stop();
    } catch (_) {
      // Nothing to stop.
    }

    Timer(const Duration(milliseconds: 1000), () {
      if (!_listening || session != _session) return;

      final words = _lastWords.trim();
      if (words.isEmpty) {
        _finish(
          const VoiceCommandResult(
            VoiceCommand.unknown,
            problem: VoiceProblem.noSpeech,
          ),
        );
        return;
      }

      final command = parseVoiceCommand(words);
      _finish(
        VoiceCommandResult(
          command,
          words: words,
          problem: command == VoiceCommand.unknown
              ? VoiceProblem.noMatch
              : VoiceProblem.none,
        ),
      );
    });
  }

  /// Stops a listen that is in progress, e.g. when the app is backgrounded.
  Future<void> cancel() async {
    if (!_listening) return;
    try {
      await _speech.cancel();
    } catch (_) {
      // Nothing to release.
    }
    _finish(
      const VoiceCommandResult(
        VoiceCommand.unknown,
        problem: VoiceProblem.noSpeech,
      ),
    );
  }

  Future<bool> _ensureReady() async {
    final wanted = LanguageService.instance.language.value;
    if (wanted != _language) {
      _language = wanted;
      _localeDirty = true;
    }

    if (_initialized) {
      if (_localeDirty) {
        await _selectLocale(_language);
        _localeDirty = false;
      }
      return _available && !_localeMissing;
    }

    _permissionError = false;
    try {
      _available = await _speech.initialize(
        onError: _onError,
        finalTimeout: const Duration(seconds: 1),
      );
    } catch (error) {
      if (kDebugMode) debugPrint('voice: initialize failed $error');
      _available = false;
    }

    if (!_available) {
      // Do not cache a failure: the user may grant permission in Settings and
      // try again without restarting the app.
      _permissionError = await _micDenied();
      _initialized = false;
      return false;
    }

    await _selectLocale(_language);
    _localeDirty = false;
    if (_localeMissing) return false;
    _initialized = true;
    if (kDebugMode) {
      debugPrint(
        'voice: ready locale=${_localeId ?? 'system'} '
        'language=${_language.label}',
      );
    }
    return true;
  }

  /// True when the microphone permission is missing.
  ///
  /// `initialize() == false` can mean no recogniser or no permission, so the
  /// permission is checked directly instead of guessing.
  Future<bool> _micDenied() async {
    try {
      final status = await Permission.microphone.status;
      return status.isDenied || status.isPermanentlyDenied;
    } catch (_) {
      return false;
    }
  }

  /// Chooses the best locale the phone offers for [language].
  ///
  /// The exact Indian locale is preferred, then any locale in that language.
  /// If the phone offers none, [_localeMissing] is set so the user hears
  /// “not installed” instead of an English model quietly failing every
  /// Hindi command.
  Future<void> _selectLocale(CueLanguage language) async {
    final wanted = language.speechLocale;
    final prefix = language.isHindi ? 'hi' : 'en';

    try {
      final locales = await _speech.locales();
      String? exact;
      String? sameLanguage;

      for (final locale in locales) {
        final id = locale.localeId;
        final normalised = id.toLowerCase().replaceAll('-', '_');
        if (normalised == wanted.toLowerCase()) {
          exact = id;
          break;
        }
        if (sameLanguage == null && normalised.split('_').first == prefix) {
          sameLanguage = id;
        }
      }

      _localeId = exact ?? sameLanguage;
      _localeMissing = _localeId == null;
    } catch (_) {
      // If locales cannot be listed, the system default may still work; the
      // recogniser will report a no_match if it does not.
      _localeId = null;
      _localeMissing = false;
    }
  }

  List<String> _phrasesFor(CueLanguage language) =>
      language.isHindi ? _phrasesHindi : _phrases;

  void _onResult(int session, SpeechRecognitionResult result) {
    // A final callback from a listen that has already ended must not act on a
    // newer listen, or the previous command would be replayed by accident.
    if (session != _session || !_listening) return;

    final words = result.recognizedWords.trim();
    if (words.isEmpty) return;
    _lastWords = words;

    final command = parseVoiceCommand(words);
    if (kDebugMode) {
      debugPrint(
        'voice: heard "$words" -> ${command.name} '
        'final=${result.finalResult}',
      );
    }

    if (command != VoiceCommand.unknown) {
      unawaited(_speech.stop().catchError((_) {}));
      _finish(VoiceCommandResult(command, words: words));
      return;
    }

    if (result.finalResult) {
      _finish(
        VoiceCommandResult(
          VoiceCommand.unknown,
          words: words,
          problem: VoiceProblem.noMatch,
        ),
      );
    }
  }

  void _onError(SpeechRecognitionError error) {
    // A deliberate stop often surfaces as an error on Android; the release
    // timer below turns the last partial transcript into the result instead.
    if (_stopping) return;

    if (kDebugMode) {
      debugPrint('voice: error ${error.errorMsg} permanent=${error.permanent}');
    }

    final message = error.errorMsg.toLowerCase();
    if (message.contains('permission') ||
        message.contains('not_allowed') ||
        message.contains('not-allowed')) {
      _permissionError = true;
    }

    final problem =
        message.contains('permission') ||
            message.contains('not_allowed') ||
            message.contains('not-allowed')
        ? VoiceProblem.permissionDenied
        : message.contains('no_match') || message.contains('no-match')
        ? VoiceProblem.noMatch
        : message.contains('speech_timeout') ||
              message.contains('no_speech') ||
              message.contains('no-speech')
        ? VoiceProblem.noSpeech
        : VoiceProblem.error;

    _finish(VoiceCommandResult(VoiceCommand.unknown, problem: problem));
  }

  void _finish(VoiceCommandResult result) {
    _listening = false;
    _stopping = false;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(result);
  }
}
