import '../vision/detected_object.dart';
import 'cue_language.dart';
import 'search_target.dart';

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

  String get looking => _hi ? 'क्यू देख रहा है।' : 'Cue is looking.';

  String get lookingIntro => _hi
      ? 'क्यू देख रहा है। बोलने के लिए वॉल्यूम डाउन दबाए रखें, या मदद कहें।'
      : 'Cue is looking. Hold volume down to speak, or say help.';

  String get startingCamera => _hi ? 'कैमरा शुरू हो रहा है' : 'Starting camera';

  String get cueLooking => _hi ? 'क्यू देख रहा है' : 'Cue is looking';

  String get pausedLabel => _hi ? 'रुका हुआ' : 'Paused';

  String get cameraProblem => _hi ? 'कैमरा समस्या' : 'Camera problem';

  String get listeningLabel => _hi ? 'सुन रहा हूँ' : 'Listening';

  String get readingLabel => _hi ? 'पढ़ रहा हूँ' : 'Reading';

  String get readyToRead => _hi ? 'पढ़ने के लिए तैयार' : 'Ready to read';

  String get listeningHint => _hi ? 'कमांड बोलें' : 'Say a command';

  String get holdVolumeHint =>
      _hi ? 'बोलने के लिए वॉल्यूम डाउन दबाए रखें' : 'Hold volume down to speak';

  String get readingPausedLabel => _hi ? 'पढ़ना रुका हुआ' : 'Reading paused';

  String get resumeReading => _hi ? 'पढ़ना जारी रखें' : 'Resume reading';

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

  String get checkingForText =>
      _hi ? 'लिखा हुआ पाठ ढूँढ रहा हूँ।' : 'Checking for text.';

  String get help => _hi
      ? 'नियंत्रण। बोलने के लिए वॉल्यूम डाउन दबाए रखें। कमांड: पढ़ो, रुको, दोहराओ, ठहरो, जारी रखो, अगला, पिछला, शुरू से, धीरे, तेज़, समय, तारीख, लोकेशन, और मोड: पाठ, वस्तु, नोट। अभी पढ़ने के लिए दो बार टैप करें। कंप्यूटर स्क्रीन में दिख रहे बदलाव सुनने के लिए स्क्रीन देखो कहें।'
      : 'Controls. Hold volume down to speak. Commands: read, stop, repeat, pause, resume, next, back, start over, slower, faster, time, date, location, and modes: text, object, banknote. Double tap to read now. Say Watch the screen to hear visible changes on a computer screen.';

  String get helpHowTo => _hi
      ? 'बोलने के लिए वॉल्यूम डाउन दबाए रखें।'
      : 'Hold volume down to speak.';

  String get shakeForHelp => _hi
      ? 'मदद के लिए फ़ोन को दो बार दाएँ-बाएँ हिलाएँ, या स्क्रीन को दबाए रखें।'
      : 'For help, move the phone side to side twice, or touch and hold the screen.';

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

  String get fastest => _hi ? 'सबसे तेज़ गति।' : 'Fastest speed.';

  String get slowest => _hi ? 'सबसे धीमी गति।' : 'Slowest speed.';

  String get fasterConfirmation => _hi ? 'तेज़ गति।' : 'Faster.';

  String get slowerConfirmation => _hi ? 'धीमी गति।' : 'Slower.';

  String get previewShown => _hi ? 'पूर्वावलोकन दिखाया गया।' : 'Preview shown.';

  String get alreadyPaused => _hi ? 'पहले से रुका हुआ है।' : 'Already paused.';

  /// The answer to "what mode am I in?".
  String modeAnswer(String englishLabel) => _hi
      ? 'अभी ${modeName(englishLabel)} मोड में हूँ।'
      : 'You are in ${englishLabel.toLowerCase()} mode.';

  String get languageAnswer => _hi
      ? 'मैं हिंदी में हूँ। बदलने के लिए भाषा बदलो कहें।'
      : 'I am using English. Say change language to switch.';

  String torchStateAnswer(bool on) => on
      ? (_hi ? 'टॉर्च चालू है।' : 'The torch is on.')
      : (_hi ? 'टॉर्च बंद है।' : 'The torch is off.');

  String speedAnswer({required bool slowest, required bool fastest}) {
    if (slowest) {
      return _hi ? 'यह सबसे धीमी गति है।' : 'This is the slowest speed.';
    }
    if (fastest) {
      return _hi ? 'यह सबसे तेज़ गति है।' : 'This is the fastest speed.';
    }
    return _hi
        ? 'यह सामान्य पढ़ने की गति है।'
        : 'This is the normal reading speed.';
  }

  String get neverMind => _hi ? 'ठीक है।' : 'Okay.';

  String get alreadyRunning =>
      _hi ? 'क्यू पहले से चल रहा है।' : 'Already running.';

  String get readingPaused => _hi ? 'पढ़ना रुका।' : 'Reading paused.';

  // --- Navigation -----------------------------------------------------------

  String get endOfPage => _hi ? 'पेज का अंत।' : 'End of page.';

  String get startOfPage => _hi ? 'पेज की शुरुआत।' : 'Start of page.';

  String get nothingToRead => _hi
      ? 'अभी पढ़ने के लिए कुछ नहीं है। पढ़ो कहें।'
      : 'Nothing to read yet. Say read.';

  String get nothingToRepeat =>
      _hi ? 'दोहराने के लिए कुछ नहीं है।' : 'Nothing to repeat yet.';

  // --- Reading honestly -----------------------------------------------------

  String get aimAtText => _hi
      ? 'पीछे का कैमरा लिखे हुए पाठ की ओर रखें।'
      : 'Point the rear camera at the text.';

  String get lightForText => _hi
      ? 'पाठ पर थोड़ी और रोशनी डालकर देखें।'
      : 'Try adding more light to the text.';

  String get steadyForText => _hi
      ? 'कैमरे को पाठ की ओर रखते हुए फ़ोन स्थिर रखें।'
      : 'Hold the phone steady with the camera aimed at the text.';

  String get somethingThere =>
      _hi ? 'पहचान नहीं पाया।' : 'Unrecognised object.';

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
      ? 'वस्तु मोड। किसी चीज़ की ओर कैमरा करके दो बार टैप करें। चाबी के लिए चाबी खोजो कहें।'
      : 'Object mode. Point at an item and double tap, or say Find my keys.';

  /// Banknote mode is built for English first.
  ///
  /// Hindi is frozen for the pilot, so there is no new Hindi instruction here.
  /// The existing one-word mode name is used instead of inventing wording.
  String get banknoteModeAnnouncement => _hi
      ? modeName('Banknote')
      : 'Banknote mode. Hold one note flat, whole note in view. '
            'Double tap to check.';

  /// The value of a note Cue is sure about.
  String banknoteAnswer(int rupees) => spokenRupeeAmount(rupees, hindi: _hi);

  String get banknoteNotRecognised => _hi
      ? somethingThere
      : 'I cannot read the note. Move the phone back until the whole note '
            'fits, then hold still.';

  /// A value Cue saw but could not corroborate in one frame.
  ///
  /// Spoken only with an explicit hedge, so a close-up that hides the rest of
  /// the note is still useful without pretending the value is certain.
  String banknoteUncertain(int rupees) => _hi
      ? somethingThere
      : 'I think it is '
            '${spokenRupeeAmount(rupees, hindi: false).toLowerCase()} '
            'I cannot see the whole note.';

  String get banknoteSeveralNotes => _hi
      ? somethingThere
      : 'More than one note value is in view. Show one note at a time.';

  String get textModeAnnouncement =>
      '${_hi ? 'पाठ मोड।' : 'Text mode.'} $textTapHint';

  String get textScreenGuide => _hi
      ? 'कैमरा कंप्यूटर स्क्रीन की ओर रखें और फ़ोन स्थिर रखें। क्यू स्क्रीन पर दिख रहे बदलाव और निर्देश बताएगा। बंद करने के लिए स्क्रीन देखना बंद कहें।'
      : 'Point the rear camera at the display and hold it steady. Cue will report visible changes and prompts. Say Stop watching to finish.';

  String get watchScreen => _hi ? 'स्क्रीन देखें' : 'Watch screen';
  String get watchingScreen => _hi ? 'स्क्रीन देख रहा है' : 'Watching screen';
  String get stopWatchingScreen =>
      _hi ? 'स्क्रीन देखना बंद करें' : 'Stop watching';
  String get screenWatchStopped =>
      _hi ? 'स्क्रीन देखना बंद किया।' : 'Screen watch stopped.';
  String get screenMovement => _hi
      ? 'स्क्रीन के दृश्य में हलचल दिख रही है।'
      : 'I can see movement in the screen view.';
  String screenUnchanged(int seconds) => _hi
      ? 'स्क्रीन के दृश्य में कम से कम $seconds सेकंड से कोई बदलाव नहीं दिखा।'
      : 'No visible change in the screen view for at least $seconds seconds.';
  String get screenUnclear => _hi
      ? 'स्क्रीन साफ़ नहीं दिख रही। कैमरा स्क्रीन की ओर रखें और फ़ोन स्थिर रखें।'
      : 'The screen view is unclear. Aim at the display and hold the phone steady.';

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

  String get semanticsText => _hi ? 'क्यू। पाठ मोड।' : 'Cue. Text mode.';

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

  String get textTapHint => _hi
      ? 'कैमरा पाठ की ओर रखें, फिर पढ़ने के लिए दो बार टैप करें।'
      : 'Point the camera at the text, then double tap to read.';

  String get objectTapHint => _hi
      ? 'किसी चीज़ की ओर कैमरा करके दो बार टैप करें।'
      : 'Point at an item and double tap to identify it.';

  String objectTooDark({required bool torchOn}) {
    if (torchOn) {
      return _hi
          ? 'टॉर्च चालू है। फिर भी वस्तु साफ़ नहीं दिख रही।'
          : 'Torch is on. I still can’t identify the object.';
    }
    return _hi
        ? 'इस दृश्य में वस्तु साफ़ नहीं दिख रही।'
        : 'I can’t identify the object clearly in this view.';
  }

  String get torchUnavailable =>
      _hi ? 'टॉर्च बदल नहीं सका।' : 'I couldn’t change the torch.';

  String get objectTooBlurry => _hi
      ? 'तस्वीर साफ़ नहीं है। फ़ोन स्थिर रखकर फिर कोशिश करें।'
      : 'The view is unclear. Hold still and try again.';
  String get objectScanUnavailable => _hi
      ? 'अभी चीज़ें पहचानने में दिक्कत है। फिर से कोशिश करें।'
      : 'Object detection is unavailable right now. Try again.';

  String get checkingObjectDetails =>
      _hi ? 'चीज़ को पास से देख रहा हूँ।' : 'Checking the close-up.';

  String get aimAtItem => _hi
      ? 'चीज़ पहचानने में मुश्किल हो रही है। एक चीज़ पीछे के कैमरे के सामने रखें और फ़ोन स्थिर रखें।'
      : 'I’m unsure what’s in view. Hold one item steady in front of the rear camera.';

  String visibleObjectText(String text) =>
      _hi ? 'इस हिस्से में लिखा है, $text।' : 'The visible text reads, $text.';

  String lastScan(String text) =>
      _hi ? 'पिछला जवाब: $text' : 'Last answer: $text';

  String get findItem => _hi ? 'चीज़ खोजें' : 'Find an item';
  String get itemName => _hi ? 'चीज़ का नाम' : 'Item name';
  String get typeItemName => _hi ? 'नाम लिखें' : 'Type a name';
  String get sayItemName => _hi ? 'नाम बोलें' : 'Say the name';
  String get sayWhatToFind => _hi ? 'बताएँ क्या खोजना है' : 'Say what to find';
  String finderPrompt({required bool hasVolumeShortcut}) {
    if (hasVolumeShortcut) {
      return _hi
          ? 'क्या खोजना है? आवाज़ कम करने वाला बटन दबाकर रखें और नाम बोलें, जैसे चाबी।'
          : 'What should I find? Hold volume down and say a name, like keys.';
    }
    return _hi
        ? 'बताएँ क्या खोजना है चुनें और नाम बोलें, जैसे चाबी।'
        : 'Choose Say what to find and say a name, like keys.';
  }

  String get startSearch => _hi ? 'खोज शुरू करें' : 'Start search';
  String get commonItems => _hi ? 'आम चीज़ें' : 'Common items';
  String get moreCommonItems => _hi ? 'और आम चीज़ें' : 'More common items';
  String get myItems => _hi ? 'मेरी चीज़ें' : 'My items';
  String get teachItem => _hi ? 'नई चीज़ सिखाएँ' : 'Teach an item';
  String get cancel => _hi ? 'रद्द करें' : 'Cancel';
  String get next => _hi ? 'आगे' : 'Continue';
  String get startCapture => _hi ? 'फ़ोटो लेना शुरू करें' : 'Start capture';
  String get capturingExample => _hi ? 'फ़ोटो ली जा रही है' : 'Taking photo';
  String get retryCapture => _hi ? 'फिर से फ़ोटो लें' : 'Retry capture';
  String get changeItemName => _hi ? 'नाम बदलें' : 'Change name';
  String get saveItem => _hi ? 'चीज़ सहेजें' : 'Save item';
  String get savingItem => _hi ? 'चीज़ सहेज रहे हैं' : 'Saving item';
  String get itemNameNeeded =>
      _hi ? 'चीज़ का नाम लिखें या बोलें।' : 'Enter or say an item name.';
  String get itemNameTooLong =>
      _hi ? 'नाम 60 अक्षरों तक रखें।' : 'Use an item name up to 60 characters.';
  String get confirmReplace => _hi ? 'बदलें' : 'Replace';
  String get removeItem => _hi ? 'हटाएँ' : 'Remove';
  String replaceItemQuestion(String name) =>
      _hi ? '$name की फ़ोटो बदलें?' : 'Replace the photos for $name?';
  String removeItemQuestion(String name) =>
      _hi ? '$name को हटाएँ?' : 'Remove $name?';
  String removeItemLabel(String name) => _hi ? '$name हटाएँ' : 'Remove $name';
  String itemRemoved(String name) => _hi ? '$name हटा दिया।' : 'Removed $name.';
  String get finderUnavailable =>
      _hi ? 'कैमरा शुरू होने पर खोजें।' : 'Start the camera to use Find.';
  String get itemStoreError => _hi
      ? 'सहेजी गई चीज़ें नहीं खोल सका।'
      : 'Cue couldn’t open your saved items.';
  String get itemSaveError => _hi
      ? 'चीज़ सहेज नहीं सका। फिर से कोशिश करें।'
      : 'Cue couldn’t save the item. Try again.';
  String get itemRemoveError => _hi
      ? 'चीज़ हटा नहीं सका। फिर से कोशिश करें।'
      : 'Cue couldn’t remove the item. Try again.';
  String get itemCaptureError => _hi
      ? 'फ़ोटो नहीं ले सका। कैमरा जाँचकर फिर से कोशिश करें।'
      : 'Cue couldn’t take the photo. Check the camera and try again.';
  String get itemCaptureUnclear => _hi
      ? 'चीज़ साफ़ नहीं दिखी। उसे छूकर उसकी जगह पता करें और फ़ोन उसके ठीक ऊपर रखें। फिर हाथ हटा लें।'
      : 'The item wasn’t clear. Find it by touch, hold the rear camera directly above it, and move your hand away.';
  String get itemCaptureDifferent => _hi
      ? 'यह फ़ोटो पिछली फ़ोटो से अलग है। फ़ोन उसी चीज़ के ठीक ऊपर रखें।'
      : 'This photo looks different from the earlier one. Hold the phone over the same item.';
  String get itemCaptureDark => _hi
      ? 'फ़ोटो के लिए रोशनी कम है। चीज़ को रोशनी वाली जगह पर रखें।'
      : 'There’s too little light for the photo. Move the item to a brighter spot.';
  String get teachingAutoRetry => _hi
      ? 'मैं थोड़ी देर में फिर फ़ोटो लूँगा।'
      : 'I’ll try the photo again in a moment.';
  String teachingRetryControl({required bool hasVolumeShortcut}) {
    if (hasVolumeShortcut) {
      return _hi
          ? 'तैयार होने पर आवाज़ कम करने वाला बटन दबाकर रखें।'
          : 'When ready, hold volume down to retry.';
    }
    return _hi ? 'फिर से फ़ोटो लें चुनें।' : 'Choose Retry capture when ready.';
  }

  String get unrecognizedItem => _hi
      ? 'इस नाम की चीज़ सिखाएँ या सूची से चुनें।'
      : 'Teach Cue this item, or choose an item from the list.';
  String findItemNextStep(String name) => _hi
      ? '$name को खोजने के लिए पहले $name सीखो कहें। सामने की चीज़ जानने के लिए विस्तार से बताओ कहें।'
      : 'To search for $name, first say Teach my $name. To check an item in front of you, say Describe in detail.';
  String get nameNotHeard => _hi
      ? 'नाम सुनाई नहीं दिया। नाम लिखें या फिर से बोलें।'
      : 'Cue didn’t hear a name. Type it or try speaking again.';
  String teachingItem(String name) => _hi ? '$name सिखाएँ' : 'Teach $name';
  String teachNamePrompt({required bool hasVolumeShortcut}) {
    if (hasVolumeShortcut) {
      return _hi
          ? 'कौन-सी चीज़ याद रखनी है? आवाज़ कम करने वाला बटन दबाकर रखें और नाम बोलें, जैसे नीला बटुआ।'
          : 'What should Cue remember? Hold volume down and say a name, like blue wallet.';
    }
    return _hi
        ? 'कौन-सी चीज़ याद रखनी है? नाम बोलें चुनें और उसका नाम बोलें।'
        : 'What should Cue remember? Choose Say the name and speak the item’s name.';
  }

  String teachPlacement({required bool hasVolumeShortcut}) {
    final start = hasVolumeShortcut
        ? (_hi
              ? 'तैयार होने पर आवाज़ कम करने वाला बटन दबाकर रखें।'
              : 'When ready, hold volume down.')
        : (_hi
              ? 'तैयार होने पर फ़ोटो लेना शुरू करें चुनें।'
              : 'When ready, choose Start capture.');
    return _hi
        ? 'चीज़ को खाली सतह पर रखें। उसे छूकर उसकी जगह पता करें। पीछे का कैमरा उस जगह से एक बित्ते की दूरी पर ठीक ऊपर रखें और नीचे की ओर करें। चीज़ से हाथ हटा लें। $start क्यू तीन फ़ोटो लेकर चीज़ सहेजेगा।'
        : 'Put the item on a clear surface. Find it by touch. Hold the rear camera one handspan above that spot, pointing straight down. Move your other hand away. $start I’ll guide you through three photos and save the item.';
  }

  String teachingProgress(int count, int total) =>
      _hi ? '$total में से $count फ़ोटो' : '$count of $total photos';
  String teachingPrompt(int count) => switch (count) {
    0 =>
      _hi
          ? 'पहली फ़ोटो के लिए फ़ोन स्थिर रखें।'
          : 'Hold still for the first photo.',
    1 =>
      _hi
          ? 'तीन में से एक फ़ोटो ठीक है। फ़ोन को थोड़ा ऊपर उठाएँ। उसे चीज़ के ठीक ऊपर रखें।'
          : 'One of three photos accepted. Lift the phone a little, keeping it directly above the item.',
    _ =>
      _hi
          ? 'तीन में से दो फ़ोटो ठीक हैं। फ़ोन को थोड़ा तिरछा करें। कैमरा चीज़ की ओर रखें।'
          : 'Two of three photos accepted. Tilt the phone slightly and keep it pointed at the item.',
  };
  String get holdForPhoto => _hi ? 'अब फ़ोन स्थिर रखें।' : 'Hold still now.';
  String itemTaught(String name) => _hi
      ? '$name सहेजा गया। अगली बार $name खोजो कहें।'
      : '$name is ready to find. Say Find $name, or choose it under My items.';
  String findingItem(String name) =>
      _hi ? '$name खोज रहे हैं' : 'Finding $name';
  String searchingItem(SearchTarget item) => _hi
      ? '${item.hindi} की तलाश शुरू। कैमरा सतह की ओर रखें और धीरे-धीरे घुमाएँ।'
      : 'Looking for your ${item.english.toLowerCase()}. Aim at the surface and sweep slowly.';
  String searchingNamedItem(String name) => _hi
      ? '$name की तलाश शुरू। कैमरा सतह की ओर रखें और धीरे-धीरे घुमाएँ।'
      : 'Looking for $name. Aim at the surface and sweep slowly.';
  String get itemSearchHint => _hi
      ? 'फ़ोन थोड़ी देर स्थिर रखें, फिर कैमरे का कोण थोड़ा बदलें।'
      : 'Hold the phone still for a moment, then try another angle.';
  String get itemCandidateHint => _hi
      ? 'शायद चीज़ दिखी है। जाँच के लिए फ़ोन स्थिर रखें।'
      : 'Possible match. Hold the phone still while I check.';
  String get itemSearchUnavailable => _hi
      ? 'चीज़ खोजने की सुविधा अभी उपलब्ध नहीं है। फिर से कोशिश करें।'
      : 'Item search is unavailable right now. Try again.';
  String itemNotSeen(SearchTarget item) => _hi
      ? 'खोज पूरी हुई। ${item.hindi} का पता नहीं चला।'
      : 'Search finished. I couldn’t spot your ${item.english.toLowerCase()}.';
  String namedItemNotSeen(String name) => _hi
      ? 'खोज पूरी हुई। $name का पता नहीं चला।'
      : 'Search finished. I couldn’t spot $name.';
  String personalItemFound(
    String name,
    ObjectDirection? direction,
  ) => switch (direction) {
    ObjectDirection.left =>
      _hi ? 'बाईं ओर $name जैसा दिख रहा है।' : 'Match for $name on your left.',
    ObjectDirection.right =>
      _hi ? 'दाईं ओर $name जैसा दिख रहा है।' : 'Match for $name on your right.',
    _ => _hi ? 'कैमरे में $name जैसा दिख रहा है।' : 'Match for $name in view.',
  };
  String get stopSearch => _hi ? 'खोज बंद करें' : 'Stop search';
  String get searchStopped => _hi ? 'खोज बंद।' : 'Search stopped.';

  String get objectHelp => _hi
      ? 'किसी चीज़ की ओर कैमरा करके दो बार टैप करें। पूरे दृश्य के लिए क्या दिख रहा है कहें। चीज़ पर लिखा हुआ सुनने के लिए विस्तार से बताओ कहें। चाबी खोजो कहें या चीज़ खोजें चुनें। चीज़ मिलने पर फ़ोन दो बार हल्का और फिर ज़ोर से कंपन करेगा। अपनी चीज़ जोड़ने के लिए नीला बटुआ सीखो कहें। ऑटो विवरण चालू या बंद कहें। मोड बदलने के लिए दाएँ या बाएँ स्वाइप करें।'
      : 'Point at an item and double tap to identify it. For the whole view, say What do you see. To hear markings on the item, say Describe in detail. Say Find my keys or choose Find an item. Two quick pulses and a stronger finish signal a match. To add your own item, say Teach my blue wallet. Say Automatic descriptions on or off. Swipe sideways to change mode.';

  String autoDescriptions(bool enabled) => _hi
      ? (enabled ? 'ऑटो विवरण चालू' : 'ऑटो विवरण बंद')
      : (enabled ? 'Automatic descriptions on' : 'Automatic descriptions off');

  String get describeNow => _hi ? 'विवरण सुनें' : 'Describe now';

  String get describeInDetail => _hi ? 'विस्तार से बताओ' : 'Describe in detail';

  String get actionRepeat => _hi ? 'पिछला दोहराओ' : 'Repeat last result';

  String get actionStop => _hi ? 'बोलना बंद करो' : 'Stop speaking';

  String get actionPauseResume => _hi ? 'ठहरो या जारी रखो' : 'Pause or resume';

  String get actionHelp => _hi ? 'मदद' : 'Help';

  String get actionPreview => _hi ? 'पूर्वावलोकन दिखाओ' : 'Show preview';

  String get actionSlower => _hi ? 'धीरे बोलो' : 'Slower speech';

  String get actionFaster => _hi ? 'तेज़ बोलो' : 'Faster speech';

  String get actionSpeakCommand => _hi ? 'कमांड बोलो' : 'Speak a command';

  String get actionChangeMode => _hi ? 'मोड बदलो' : 'Change mode';

  String get actionNext => _hi ? 'अगला वाक्य' : 'Next sentence';

  String get actionPrevious => _hi ? 'पिछला वाक्य' : 'Previous sentence';

  String get actionStartOver => _hi ? 'शुरू से पढ़ो' : 'Start over';

  String get actionLanguage => _hi ? 'भाषा बदलो' : 'Change language';

  String get actionTime => _hi ? 'समय बताओ' : 'Tell me the time';

  String get actionDate => _hi ? 'तारीख बताओ' : "Tell me today's date";

  String get actionLocation => _hi ? 'लोकेशन बताओ' : 'Tell me my location';

  String get actionBattery => _hi ? 'बैटरी बताओ' : 'Tell me the battery';

  String get actionProgress => _hi ? 'कहाँ तक पढ़ा' : 'Reading progress';

  String get actionColour => _hi ? 'रंग बताओ' : 'Tell me the colour';

  String get actionLeft => _hi ? 'बाईं ओर क्या है' : 'What is on my left';

  String get actionRight => _hi ? 'दाईं ओर क्या है' : 'What is on my right';
}

/// The value of a confirmed banknote, as Cue says it.
///
/// English uses words, because "five hundred rupees" is easier to follow than
/// "500 rupees". Hindi is frozen for the pilot, so it speaks the digits and
/// lets the installed Hindi voice read them; that adds no new Hindi wording.
String spokenRupeeAmount(int rupees, {required bool hindi}) {
  if (hindi) return '$rupees';
  return switch (rupees) {
    10 => 'Ten rupees.',
    20 => 'Twenty rupees.',
    50 => 'Fifty rupees.',
    100 => 'One hundred rupees.',
    200 => 'Two hundred rupees.',
    500 => 'Five hundred rupees.',
    2000 => 'Two thousand rupees.',
    _ => '$rupees rupees.',
  };
}
