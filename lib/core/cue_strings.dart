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
      ? 'क्यू देख रहा है। कैमरा पाठ पर रखें।'
      : 'Cue is looking. Point the camera at text.';

  String get lookingIntro => _hi
      ? 'क्यू देख रहा है। कैमरा पाठ पर रखें। आवाज़ से कमांड देने के लिए '
            'वॉल्यूम डाउन बटन आधा सेकंड दबाए रखें, बोलें, फिर छोड़ दें। '
            'कमांड सुनने के लिए मदद कहें।'
      : 'Cue is looking. Point the camera at text. To give a voice command, '
            'hold the volume down button for half a second, speak, then let '
            'go. Say help to hear the commands.';

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
      ? 'क्यू को कैमरा चाहिए। दोबारा कोशिश के लिए दो बार टैप करें और फ़ोन के पूछने '
            'पर अनुमति दें।'
      : 'Cue needs the camera to work. Double tap to try again and allow '
            'camera access when the phone asks.';

  String get cameraPermissionBlocked => _hi
      ? 'कैमरा क्यू के लिए बंद है। सेटिंग, अनुमतियाँ, कैमरा में जाकर क्यू को '
            'अनुमति दें।'
      : 'Camera access is switched off for Cue. Open Settings, then '
            'Permissions, then Camera, and allow it.';

  String get cameraNoDevice => _hi
      ? 'इस फ़ोन में कैमरा नहीं मिला।'
      : 'No camera was found on this phone.';

  String get cameraCouldNotStart => _hi
      ? 'कैमरा शुरू नहीं हो सका। कोई दूसरा ऐप कैमरा इस्तेमाल कर रहा हो तो उसे '
            'बंद करें, फिर दो बार टैप करें।'
      : 'The camera could not start. Close any other app that is using it, '
            'then double tap to try again.';

  String get retryHint =>
      _hi ? 'फिर कोशिश करने के लिए दो बार टैप करें' : 'Double tap to try again';

  // --- Controls -------------------------------------------------------------

  String get paused => _hi
      ? 'रुका हुआ। जारी रखने के लिए दो बार टैप करें।'
      : 'Paused. Double tap to resume.';

  String get readingNow => _hi ? 'पढ़ रहा हूँ।' : 'Reading now.';

  String get help => _hi
      ? 'नियंत्रण। आवाज़ कमांड के लिए वॉल्यूम डाउन बटन आधा सेकंड दबाए रखें, '
            'बोलें, फिर छोड़ें। पढ़ो, रुको, दोहराओ, या मदद कहें। अगला, '
            'पिछला, शुरू से, ठहरो, जारी रखो, धीरे, तेज़, या मोड भी कह सकते '
            'हैं। दो बार टैप करने से अभी पढ़ता है। मोड बदलने के लिए बगल में '
            'स्वाइप करें।'
      : 'Controls. Hold the volume down button for half a second, speak, then '
            'let go. Say read, stop, repeat, or help. You can also say next, '
            'back, start over, pause, resume, slower, faster, or a mode. '
            'Double tap reads now. Swipe sideways changes mode. The actions '
            'menu has the same controls.';

  String get helpHowTo => _hi
      ? 'आवाज़ कमांड के लिए वॉल्यूम डाउन बटन आधा सेकंड दबाए रखें, बोलें, फिर '
            'छोड़ें।'
      : 'Hold the volume down button for half a second, speak, then let go.';

  String get fastest =>
      _hi ? 'यह सबसे तेज़ गति है।' : 'This is the fastest speed.';

  String get slowest =>
      _hi ? 'यह सबसे धीमी गति है।' : 'This is the slowest speed.';

  String get fasterConfirmation => _hi
      ? 'तेज़। यह नई पढ़ने की गति है।'
      : 'Faster. This is the new reading speed.';

  String get slowerConfirmation => _hi
      ? 'धीरे। यह नई पढ़ने की गति है।'
      : 'Slower. This is the new reading speed.';

  String get previewShown => _hi
      ? 'पूर्वावलोकन पाँच सेकंड के लिए दिखाया गया।'
      : 'Preview shown for five seconds.';

  String get alreadyPaused => _hi ? 'पहले से रुका हुआ है।' : 'Already paused.';

  String get alreadyRunning =>
      _hi ? 'क्यू पहले से चल रहा है।' : 'Cue is already running.';

  String get readingPaused => _hi
      ? 'पढ़ना रुका। जारी रखने के लिए जारी रखो कहें।'
      : 'Reading paused. Say resume to continue.';

  // --- Navigation -----------------------------------------------------------

  String get endOfPage =>
      _hi ? 'यह पेज का अंत है।' : 'That is the end of the page.';

  String get startOfPage =>
      _hi ? 'यह पेज की शुरुआत है।' : 'That is the start of the page.';

  String get nothingToRead => _hi
      ? 'अभी कुछ नहीं पढ़ा जा रहा। पेज पर कैमरा रखें और पढ़ो कहें।'
      : 'Nothing is being read yet. Point at text and say read.';

  String get nothingToRepeat =>
      _hi ? 'अभी दोहराने के लिए कुछ नहीं है।' : 'Nothing to repeat yet.';

  // --- Reading honestly -----------------------------------------------------

  String get notSureNoText => _hi
      ? 'मुझे यकीन नहीं है। मुझे पाठ नहीं दिख रहा। फ़ोन स्थिर रखें और पेज पर '
            'कैमरा रखें।'
      : 'I am not sure. I cannot see text. Hold steady and point at the page.';

  String get marksNotReadable => _hi
      ? 'मुझे निशान दिख रहे हैं, लेकिन मैं उन्हें पढ़ नहीं सकता। छपा हुआ पाठ '
            'सबसे अच्छा काम करता है।'
      : 'I can see marks, but I cannot read them. Printed text works best.';

  String get somethingThere => _hi
      ? 'कुछ दिख रहा है, लेकिन मैं नहीं बता सकता कि क्या है।'
      : 'I see something, but I cannot tell what it is.';

  // --- Language -------------------------------------------------------------

  String get languageHindi => _hi ? 'हिंदी' : 'Hindi';

  String get languageEnglish => _hi ? 'अंग्रेज़ी' : 'English';

  String get switchedToHindi => 'अब हिंदी में पढ़ूँगा।';

  String get switchedToEnglish => 'Now reading in English.';

  String get hindiDetected => _hi
      ? 'हिंदी पाठ मिला। हिंदी में बदल रहा हूँ।'
      : 'Hindi text detected. Switching to Hindi.';

  String get englishDetected => _hi
      ? 'अंग्रेज़ी पाठ मिला। अंग्रेज़ी में बदल रहा हूँ।'
      : 'English text detected. Switching to English.';

  String get alreadyHindi => 'पहले से हिंदी में हूँ।';

  String get alreadyEnglish => 'Already in English.';

  String get hindiVoiceMissing => _hi
      ? 'हिंदी आवाज़ इस फ़ोन में नहीं मिली।'
      : 'Hindi voice is not installed on this phone. Staying in English.';

  String get englishVoiceMissing => _hi
      ? 'अंग्रेज़ी आवाज़ उपलब्ध नहीं है। हिंदी में रह रहा हूँ।'
      : 'The English voice is unavailable. Staying in English.';

  // --- Modes ----------------------------------------------------------------

  String get textModeAnnouncement => _hi
      ? 'पाठ मोड। छपे हुए पाठ पर कैमरा रखें।'
      : 'Text mode. Point at printed text.';

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
}
