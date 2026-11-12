import 'cue_language.dart';

/// The words Cue speaks and shows.
///
/// Everything the user hears is selected from one place, so switching the
/// language cannot leave half the app in English. The English strings are the
/// originals from the specification; the Hindi strings say the same thing in
/// the same order, because a blind user navigates by remembered phrasing.
class CueStrings {
  const CueStrings(this.language);

  final CueLanguage language;

  bool get _hi => language.isHindi;

  // --- Starting and status --------------------------------------------------

  String get looking => _hi
      ? 'क्यू देख रहा है।'
      : 'Cue is looking.';

  String get lookingIntro => _hi
      ? 'क्यू देख रहा है। बोलने के लिए वॉल्यूम डाउन दबाए रखें, या मदद कहें।'
      : 'Cue is looking. Hold volume down to speak, or say help.';

  String get startingCamera => _hi ? 'कैमरा शुरू हो रहा है' : 'Starting camera';

  String get cueLooking => _hi ? 'क्यू देख रहा है' : 'Cue is looking';

  String get pausedLabel => _hi ? 'रुका हुआ' : 'Paused';

  String get cameraProblem => _hi ? 'कैमरा समस्या' : 'Camera problem';

  String get listeningLabel => _hi ? 'सुन रहा हूँ' : 'Listening';

  String get readingLabel => _hi ? 'पढ़ रहा हूँ' : 'Reading';

  String get listeningHint => _hi ? 'कमांड बोलें' : 'Say a command';

  String get holdVolumeHint =>
      _hi ? 'बोलने के लिए वॉल्यूम डाउन दबाए रखें' : 'Hold volume down to speak';

  String get readingPausedLabel => _hi ? 'पढ़ना रुका हुआ' : 'Reading paused';

  String get resumeHint =>
      _hi ? 'जारी रखने के लिए दो बार टैप करें' : 'Double tap to resume';

  String get cameraPermissionDenied => _hi
      ? 'क्यू को कैमरा अनुमति चाहिए। दोबारा कोशिश के लिए दो बार टैप करें।'
      : 'Cue needs camera access. Double tap to try again and allow access.';

  String get microphoneAsk => _hi
      ? 'आवाज़ से कमांड देने के लिए क्यू को माइक्रोफ़ोन चाहिए। फ़ोन जो अनुमति '
            'माँगे, उसे स्वीकार करें।'
      : 'To take voice commands, Cue needs the microphone. Allow it when the '
            'phone asks.';

  String get microphoneBlocked => _hi
      ? 'माइक्रोफ़ोन बंद है, इसलिए आवाज़ कमांड काम नहीं करेंगे। सेटिंग, अनुमतियाँ, '
            'माइक्रोफ़ोन में जाकर क्यू को अनुमति दें।'
      : 'The microphone is off, so voice commands will not work. Open '
            'Settings, then Permissions, then Microphone, and allow Cue.';
  String get cameraPermissionBlocked => _hi
      ? 'कैमरा अनुमति बंद है। सेटिंग में जाकर क्यू को अनुमति दें।'
      : 'Camera access is blocked. Allow it in device Settings.';

  String get cameraNoDevice => _hi
      ? 'इस फ़ोन में कैमरा नहीं मिला।'
      : 'No camera was found on this phone.';

  String get cameraCouldNotStart => _hi
      ? 'कैमरा शुरू नहीं हो सका। दो बार टैप करके फिर कोशिश करें।'
      : 'Camera could not start. Double tap to try again.';

  String get retryHint =>
      _hi ? 'फिर कोशिश करने के लिए दो बार टैप करें' : 'Double tap to try again';

  // --- Controls -------------------------------------------------------------

  String get paused => _hi ? 'रुका हुआ।' : 'Paused.';

  String get readingNow => _hi ? 'पढ़ रहा हूँ।' : 'Reading now.';

  String get help => _hi
      ? 'नियंत्रण। बोलने के लिए वॉल्यूम डाउन दबाए रखें। कमांड: पढ़ो, रुको, दोहराओ, ठहरो, जारी रखो, अगला, पिछला, शुरू से, धीरे, तेज़, समय, तारीख, लोकेशन, और मोड: पाठ, वस्तु, रंग। अभी पढ़ने के लिए दो बार टैप करें।'
      : 'Controls. Hold volume down to speak. Commands: read, stop, repeat, pause, resume, next, back, start over, slower, faster, time, date, location, and modes: text, object, colour. Double tap to read now.';

  String get helpHowTo => _hi
      ? 'बोलने के लिए वॉल्यूम डाउन दबाए रखें।'
      : 'Hold volume down to speak.';

  // --- Natural questions ----------------------------------------------------

  String get cueName => _hi
      ? 'मैं क्यू हूँ। मैं पढ़कर सुनाता हूँ और कैमरे के सामने की चीज़ें बताता '
            'हूँ।'
      : 'I am Cue. I read text aloud and describe what the camera sees.';

  String get cueReady => _hi
      ? 'मैं ठीक हूँ। पढ़ने के लिए वॉल्यूम डाउन दबाए रखकर पढ़ो कहें।'
      : 'I am fine. Hold volume down and say read when you are ready.';

  String get cueWelcome => _hi
      ? 'कोई बात नहीं। मदद चाहिए तो मदद कहें।'
      : 'You are welcome. Say help if you need anything.';

  String get cueGreeting => _hi
      ? 'नमस्ते। पढ़ने के लिए वॉल्यूम डाउन दबाए रखकर पढ़ो कहें।'
      : 'Hello. Hold volume down and say read when you want me to read.';

  String get fastest =>
      _hi ? 'सबसे तेज़ गति।' : 'Fastest speed.';

  String get slowest =>
      _hi ? 'सबसे धीमी गति।' : 'Slowest speed.';

  String get fasterConfirmation => _hi
      ? 'तेज़ गति।'
      : 'Faster.';

  String get slowerConfirmation => _hi
      ? 'धीमी गति।'
      : 'Slower.';

  String get previewShown => _hi
      ? 'पूर्वावलोकन दिखाया गया।'
      : 'Preview shown.';

  String get alreadyPaused => _hi ? 'पहले से रुका हुआ है।' : 'Already paused.';

  String get alreadyRunning =>
      _hi ? 'क्यू पहले से चल रहा है।' : 'Already running.';

  String get readingPaused => _hi
      ? 'पढ़ना रुका।'
      : 'Reading paused.';

  // --- Navigation -----------------------------------------------------------

  String get endOfPage =>
      _hi ? 'पेज का अंत।' : 'End of page.';

  String get startOfPage =>
      _hi ? 'पेज की शुरुआत।' : 'Start of page.';

  String get nothingToRead => _hi
      ? 'अभी पढ़ने के लिए कुछ नहीं है। पढ़ो कहें।'
      : 'Nothing to read yet. Say read.';

  String get nothingToRepeat =>
      _hi ? 'दोहराने के लिए कुछ नहीं है।' : 'Nothing to repeat yet.';

  // --- Reading honestly -----------------------------------------------------

  String get notSureNoText => _hi
      ? 'पाठ नहीं दिख रहा। स्थिर रखें।'
      : 'No text visible. Hold steady.';

  String get marksNotReadable => _hi
      ? 'पाठ पढ़ा नहीं जा रहा।'
      : 'Unreadable text.';

  String get somethingThere => _hi
      ? 'पहचान नहीं पाया।'
      : 'Unrecognised object.';

  // --- Language -------------------------------------------------------------

  String get languageHindi => _hi ? 'हिंदी' : 'Hindi';

  String get languageEnglish => _hi ? 'अंग्रेज़ी' : 'English';

  String get switchedToHindi => 'अब हिंदी में पढ़ूँगा।';

  String get switchedToEnglish => 'Now reading in English.';

  String get hindiDetected => _hi
      ? 'हिंदी पाठ मिला। हिंदी आवाज़ से पढ़ रहा हूँ।'
      : 'Hindi text detected. Reading with Hindi voice.';

  String get englishDetected => _hi
      ? 'अंग्रेज़ी पाठ मिला। अंग्रेज़ी आवाज़ से पढ़ रहा हूँ।'
      : 'English text detected. Reading with English voice.';

  String get alreadyHindi => 'पहले से हिंदी में हूँ।';

  String get alreadyEnglish => 'Already in English.';

  String get hindiVoiceMissing => _hi
      ? 'हिंदी आवाज़ इस फ़ोन में नहीं मिली।'
      : 'Hindi voice is not installed on this phone. Staying in English.';

  String get englishVoiceMissing => _hi
      ? 'अंग्रेज़ी आवाज़ उपलब्ध नहीं है। हिंदी में रह रहा हूँ।'
      : 'The English voice is unavailable. Staying in English.';

  // --- Sensors and environment ----------------------------------------------

  String get holdStill => _hi ? 'फ़ोन स्थिर रखें।' : 'Hold the phone still.';

  String get tiltLeft => _hi
      ? 'फ़ोन का ऊपरी हिस्सा बाएँ घुमाएँ।'
      : 'Tilt the top of the phone to the left.';

  String get tiltRight => _hi
      ? 'फ़ोन का ऊपरी हिस्सा दाएँ घुमाएँ।'
      : 'Tilt the top of the phone to the right.';

  String get torchOn => _hi
      ? 'अंधेरे की वजह से टॉर्च चालू कर रहा हूँ। बंद करने के लिए टॉर्च बंद कहें।'
      : 'It is dark. Turning on the torch. Say torch off to switch it off.';

  String get torchTurnedOn => _hi ? 'टॉर्च चालू।' : 'Torch on.';

  String get torchTurnedOff => _hi ? 'टॉर्च बंद।' : 'Torch off.';

  String get torchAutoOff => _hi
      ? 'टॉर्च बंद कर दी। फिर से चालू करने के लिए टॉर्च चालू कहें।'
      : 'Torch off. Say torch on if you need it again.';

  // --- Modes ----------------------------------------------------------------

  String get objectModeAnnouncement => _hi
      ? 'वस्तु मोड।'
      : 'Object mode.';

  String get textModeAnnouncement => _hi
      ? 'पाठ मोड।'
      : 'Text mode.';

  String modeName(String englishLabel) {
    if (!_hi) return englishLabel;
    return switch (englishLabel) {
      'Text' => 'पाठ',
      'Object' => 'वस्तु',
      'Banknote' => 'नोट',
      'Screen' => 'स्क्रीन',
      _ => englishLabel,
    };
  }

  String notBuilt(String modeLabel) => _hi
      ? '$modeLabel मोड अभी नहीं बना है। मोड बदलने के लिए स्वाइप करें।'
      : '$modeLabel mode is not built yet. Swipe to change mode.';

  // --- TalkBack -------------------------------------------------------------

  String get semanticsStarting =>
      _hi ? 'क्यू। कैमरा शुरू हो रहा है।' : 'Cue. Starting camera.';

  String get semanticsLive => _hi ? 'क्यू। लाइव कैमरा।' : 'Cue. Live camera.';

  String get semanticsPaused => _hi ? 'क्यू। रुका हुआ।' : 'Cue. Paused.';

  String get semanticsListening =>
      _hi ? 'क्यू। कमांड सुन रहा हूँ।' : 'Cue. Listening for a command.';

  String semanticsProblem(String error) =>
      _hi ? 'क्यू। कैमरा समस्या। $error' : 'Cue. Camera problem. $error';

  String get semanticsHint => _hi
      ? 'बोलने के लिए वॉल्यूम डाउन दबाए रखें। अभी पढ़ने के लिए दो बार टैप '
            'करें। मोड बदलने के लिए बगल में स्वाइप करें। दोहराने, रोकने, '
            'ठहरने, मदद, पूर्वावलोकन, गति और भाषा के लिए क्रियाएँ मेनू का '
            'उपयोग करें।'
      : 'Hold the volume down button and speak a command. Double tap to read '
            'now. Swipe sideways to change interpretation. Use the actions '
            'menu for repeat, stop, pause, help, preview, speech speed, '
            'sentence navigation and language.';

  String get actionReadNow => _hi ? 'अभी पढ़ो' : 'Read now';

  String get actionRepeat => _hi ? 'पिछला दोहराओ' : 'Repeat last result';

  String get actionStop => _hi ? 'बोलना बंद करो' : 'Stop speaking';

  String get actionPauseResume => _hi ? 'ठहरो या जारी रखो' : 'Pause or resume';

  String get actionHelp => _hi ? 'मदद' : 'Help';

  String get actionPreview => _hi ? 'पूर्वावलोकन दिखाओ' : 'Show preview';

  String get actionSlower => _hi ? 'धीरे बोलो' : 'Slower speech';

  String get actionFaster => _hi ? 'तेज़ बोलो' : 'Faster speech';

  String get actionSpeakCommand => _hi ? 'कमांड बोलो' : 'Speak a command';

  String get actionChangeMode => _hi ? 'मोड बदलो' : 'Change interpretation';

  String get actionNext => _hi ? 'अगला वाक्य' : 'Next sentence';

  String get actionPrevious => _hi ? 'पिछला वाक्य' : 'Previous sentence';

  String get actionStartOver => _hi ? 'शुरू से पढ़ो' : 'Start over';

  String get actionLanguage => _hi ? 'भाषा बदलो' : 'Change language';

  String get actionTime => _hi ? 'समय बताओ' : 'Tell me the time';

  String get actionDate => _hi ? 'तारीख बताओ' : "Tell me today's date";

  String get actionLocation => _hi ? 'लोकेशन बताओ' : 'Tell me my location';
}
