import 'dart:async';

import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'cue_language.dart';
import 'finder_request.dart';
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

  bool get ok => problem == VoiceProblem.none;
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
    'torch on',
    'torch off',
    'turn on the torch',
    'turn off the torch',
    'light on',
    'light off',
    'what time is it',
    'what is the date',
    'where am I',
    'my location',
    'turn on location',
    'open location settings',
    'change language',
    'what is your name',
    'who are you',
    'how are you',
    'what is this',
    'what can you do',
    'thank you',
    'what mode am I in',
    'what language are you using',
    'is the torch on',
    'how fast are you reading',
    'battery',
    'what did you say',
    'never mind',
    'where was I',
    'how much is left',
    'what colour is this',
    'what is on my left',
    'what is on my right',
    'read from the top',
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
    'टॉर्च चालू',
    'टॉर्च बंद',
    'लाइट चालू',
    'लाइट बंद',
    'समय क्या है',
    'तारीख क्या है',
    'मैं कहाँ हूँ',
    'लोकेशन चालू करो',
    'लोकेशन सेटिंग',
    'भाषा बदलो',
    'तुम्हारा नाम क्या है',
    'यह क्या है',
    'धन्यवाद',
    'नमस्ते',
    'कौन सा मोड है',
    'कौन सी भाषा है',
    'टॉर्च चालू है',
    'कितनी तेज़ है',
    'बैटरी',
    'क्या कहा',
    'कुछ नहीं',
    'कहाँ था',
    'कितना बाकी है',
    'रंग क्या है',
    'मेरी बाईं ओर क्या है',
    'मेरी दाईं ओर क्या है',
  ];

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;
  bool _available = false;
  bool _listening = false;

  /// True between the call to [listen] and the microphone actually opening.
  bool _starting = false;

  /// Set when the talk key is released before the microphone opened.
  bool _stopRequested = false;
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

  /// Bumped whenever a listen is started or abandoned, including while the
  /// engine is still opening. An attempt that was superseded must not open the
  /// microphone or overwrite the state of the attempt replacing it.
  int _request = 0;

  /// True while the user has let go of the talk key and the platform is being
  /// stopped on purpose. Errors during that window are expected, not failures.
  bool _stopping = false;

  /// The last words the recogniser reported, used when the user releases the
  /// talk key before the platform sends a final result.
  String _lastWords = '';
  bool _dictating = false;

  bool get isListening => _listening;

  /// Prepares the recogniser without opening the microphone.
  ///
  /// Called when the live screen opens, so the first volume-down press is not
  /// spent initialising the engine, and so the microphone permission dialog
  /// appears before the user is already mid-sentence. A listen that starts on a
  /// cold engine can take a second to accept audio, which feels like Cue
  /// ignoring the first words.
  Future<void> prepare() async {
    if (_listening) return;
    await _ensureReady();
  }

  /// Starts one listen and waits for a command, a timeout or an error.
  ///
  /// [onReady] fires when the platform has the microphone open and is actually
  /// accepting audio. The caller should make its "speak now" signal then, not
  /// before: the recogniser can take half a second to get there, so a tone
  /// played at key-down tells the user to speak into a microphone that is still
  /// closed, and the first word is lost.
  ///
  /// The caller should stop any speech first: otherwise the microphone hears
  /// Cue's own voice.
  Future<VoiceCommandResult> listen({
    bool dictation = false,
    void Function()? onReady,
  }) async {
    if (_listening) {
      return const VoiceCommandResult(
        VoiceCommand.unknown,
        problem: VoiceProblem.busy,
      );
    }

    _starting = true;
    _stopRequested = false;
    final request = ++_request;
    final ready = await _ensureReady();
    // A second press can arrive while the engine is still opening. This
    // attempt is then obsolete and must leave the microphone to its successor.
    if (request != _request) {
      return const VoiceCommandResult(
        VoiceCommand.unknown,
        problem: VoiceProblem.busy,
      );
    }
    if (!ready) {
      _starting = false;
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

    _starting = false;
    _listening = true;
    _stopping = false;
    _lastWords = '';
    _dictating = dictation;
    _readyCallback = onReady;
    final session = ++_session;
    final completer = Completer<VoiceCommandResult>();
    _pending = completer;
    // Field diagnostics: a microphone failure is invisible otherwise, and this
    // is the one part of Cue that cannot be checked from a log after the fact.
    debugPrint('voice: listen start locale=${_localeId ?? 'default'}');

    try {
      await _speech.listen(
        onResult: (result) => _onResult(session, result),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: dictation
              ? stt.ListenMode.dictation
              : stt.ListenMode.confirmation,
          // Silence ends the command. A user who pauses to think mid-sentence
          // should not be cut off, so it is generous; the overall window is a
          // little longer than a slow command needs.
          pauseFor: const Duration(milliseconds: 2500),
          listenFor: const Duration(seconds: 8),
          localeId: _localeId,
          contextualPhrases: dictation ? const [] : _phrasesFor(_language),
        ),
      );
    } catch (error) {
      debugPrint('voice: listen failed $error');
      _finish(
        const VoiceCommandResult(
          VoiceCommand.unknown,
          problem: VoiceProblem.error,
        ),
      );
      return completer.future;
    }

    // Safety net: a platform that never sends a final result must not leave
    // the live screen stuck in "Listening". Anything already heard is used
    // rather than thrown away: a slow speaker often produces a partial
    // transcript before the platform gives up, and "I did not hear anything"
    // would be untrue.
    Timer(const Duration(seconds: 8), () {
      if (!_listening || session != _session) return;
      unawaited(_speech.stop().catchError((_) {}));
      _finish(_interpret(_lastWords));
    });

    return completer.future;
  }

  /// Ends the current listen when the user lets go of the talk key.
  ///
  /// The platform is given a moment to deliver its own final result. If it
  /// does not, the last partial transcript is used, so a quick "read" is not
  /// thrown away just because the key came up early.
  Future<void> finishListening() async {
    // Released while the engine was still opening. Remember it; the release is
    // honoured as soon as the platform reports that the microphone is live.
    if (_starting) {
      _stopRequested = true;
      return;
    }
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

      _finish(_interpret(_lastWords));
    });
  }

  /// Stops a listen that is in progress, e.g. when the app is backgrounded.
  Future<void> cancel() async {
    // The engine may still be opening. Abandon that attempt now, or it would
    // open the microphone after the user already cancelled and start acting
    // on whatever it heard.
    if (_starting) {
      _request++;
      _starting = false;
      _stopRequested = false;
      _readyCallback = null;
      return;
    }
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

    // Ask for the microphone here, as early as the user has asked to listen.
    // This avoids the plugin's combined request, which also asks for a
    // Bluetooth permission Cue does not need.
    try {
      final current = await Permission.microphone.status;
      if (!current.isGranted) {
        await Permission.microphone.request();
      }
    } catch (_) {}

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
        onStatus: _onStatus,
        finalTimeout: const Duration(seconds: 1),
        // Cue does not listen over Bluetooth; requesting that permission can
        // leave invoke initialize looking successful without an ASR backend.
        options: <stt.SpeechConfigOption>[stt.SpeechToText.androidNoBluetooth],
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

  VoiceCommandResult _interpret(String words) {
    final command = _dictating
        ? VoiceCommand.unknown
        : parseVoiceCommand(words);
    final understood =
        _dictating ||
        command != VoiceCommand.unknown ||
        FinderRequest.parse(words) != null;
    return VoiceCommandResult(
      command,
      words: words,
      problem: words.isEmpty
          ? VoiceProblem.noSpeech
          : understood
          ? VoiceProblem.none
          : VoiceProblem.noMatch,
    );
  }

  void _onResult(int session, SpeechRecognitionResult result) {
    // A final callback from a listen that has already ended must not act on a
    // newer listen, or the previous command would be replayed by accident.
    if (session != _session || !_listening) return;

    final words = result.recognizedWords.trim();
    if (words.isEmpty) return;
    _lastWords = words;

    final interpretation = _interpret(words);
    if (result.finalResult) {
      _finish(interpretation);
    } else if (!_dictating &&
        interpretation.command != VoiceCommand.unknown &&
        interpretation.command.target == null &&
        FinderRequest.parse(words) == null) {
      unawaited(_speech.stop().catchError((_) {}));
      _finish(interpretation);
    }
  }

  /// The callback to run once the platform has the microphone open.
  void Function()? _readyCallback;

  /// Turns the platform's "listening" status into the ready signal.
  void _onStatus(String status) {
    if (status != stt.SpeechToText.listeningStatus) return;
    debugPrint('voice: microphone ready');
    final ready = _readyCallback;
    _readyCallback = null;
    ready?.call();
    // The key may have come up while the engine was still opening. Now that
    // the microphone is live, honour that release instead of ignoring it and
    // waiting out the full listen window in silence.
    if (_stopRequested) unawaited(_speech.stop().catchError((_) {}));
  }

  void _onError(SpeechRecognitionError error) {
    // A deliberate stop often surfaces as an error on Android; the release
    // timer below turns the last partial transcript into the result instead.
    if (_stopping) return;

    debugPrint('voice: error ${error.errorMsg} permanent=${error.permanent}');

    // Android often reports no_match or speech_timeout immediately after a
    // usable partial transcript ("read this page" arrives as "read this").
    // The words are already known, so they are parsed before the error is
    // turned into a failure. Otherwise a command the user did say is answered
    // with "I did not understand", which is the most confusing failure of all.
    final heard = _interpret(_lastWords);
    if (heard.ok) {
      _finish(heard);
      return;
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
    _starting = false;
    _stopping = false;
    _stopRequested = false;
    _readyCallback = null;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(result);
  }
}
