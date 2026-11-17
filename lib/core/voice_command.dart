/// The spoken commands Cue understands.
///
/// Kept separate from the speech-recognition plugin so the parsing rules can be
/// unit tested without a phone, a microphone or a network.
enum VoiceCommand {
  readNow,
  repeat,
  stop,
  pause,
  resume,
  nextSentence,
  previousSentence,
  startOver,
  help,
  slower,
  faster,
  textMode,
  objectMode,
  banknoteMode,
  screenMode,
  showPreview,
  hindiMode,
  englishMode,
  torchOn,
  torchOff,
  currentTime,
  currentDate,
  location,
  locationSettings,
  toggleLanguage,
  whichLanguage,
  whoAreYou,
  howAreYou,
  thanks,
  greeting,
  whatIsThis,
  whatMode,
  torchState,
  readingSpeed,
  battery,
  repeatAnswer,
  neverMind,
  readingProgress,
  questionColour,
  whatIsLeft,
  whatIsRight,
  unknown,
}

/// Turns a recognised sentence into one command.
///
/// Recognition is noisy: it adds punctuation, changes case, and sometimes
/// inserts extra words. Matching is therefore done on normalised words, and a
/// command may appear anywhere in a short sentence ("can you read this").
/// The most specific phrases are checked first so "read again" means repeat
/// and "screen mode" does not become "show preview".
///
/// English and Hindi phrases live side by side. The parser does not need to
/// know which language the recogniser was set to: a Hindi word simply matches
/// its Hindi phrase. That also means a mixed sentence such as "next वाक्य"
/// still works, which is how people actually speak.
VoiceCommand parseVoiceCommand(String transcript) {
  final text = _normalize(transcript);
  if (text.isEmpty) return VoiceCommand.unknown;

  bool has(String phrase) {
    final clean = _normalize(phrase);
    if (clean.isEmpty) return false;
    return RegExp(
      '(^| )${RegExp.escape(clean)}( |\$)',
      unicode: true,
    ).hasMatch(text);
  }

  bool exact(String phrase) => text == _normalize(phrase);

  bool near(String word) => _near(text, word);

  // Language switching comes first: "हिंदी" must never be mistaken for a
  // read command, and "english" must not be caught by another phrase.
  if (has('hindi') ||
      has('hindi mode') ||
      has('switch to hindi') ||
      has('हिंदी') ||
      has('हिन्दी') ||
      exact('हिंदी में')) {
    return VoiceCommand.hindiMode;
  }
  if (has('english') ||
      has('english mode') ||
      has('switch to english') ||
      has('अंग्रेज़ी') ||
      has('अंग्रेजी') ||
      has('इंग्लिश')) {
    return VoiceCommand.englishMode;
  }

  // A bare "language" is a request to switch, so it is checked after the
  // explicit names above: "change language to Hindi" still sets Hindi instead
  // of blindly toggling away from it.
  if (has('change language') ||
      has('change the language') ||
      has('switch language') ||
      has('language change') ||
      exact('language') ||
      has('भाषा बदल') ||
      has('भाषा बदलो') ||
      has('भाषा बदलें') ||
      has('भाषा बदले') ||
      has('भाषा चेंज') ||
      exact('भाषा')) {
    return VoiceCommand.toggleLanguage;
  }

  // Asking which language is in use, not asking to change it. Checked after
  // the switch phrases so "change language" still switches.
  if (has('what language') ||
      has('which language') ||
      has('what language are you') ||
      has('which language are you') ||
      has('कौन सी भाषा') ||
      has('कौन भाषा') ||
      has('भाषा क्या है')) {
    return VoiceCommand.whichLanguage;
  }

  // Identity and small talk. People ask these before they ask for a reading,
  // and a blind user cannot read a "not understood" message on screen.
  if (has('what is your name') ||
      has('what s your name') ||
      has('your name') ||
      has('who are you') ||
      has('what are you') ||
      has('तुम्हारा नाम') ||
      has('आपका नाम') ||
      has('तुम कौन') ||
      has('आप कौन') ||
      exact('नाम')) {
    return VoiceCommand.whoAreYou;
  }
  if (has('how are you') ||
      has('how do you do') ||
      has('how are you doing') ||
      has('how you doing') ||
      has('कैसे हो') ||
      has('कैसी हो') ||
      has('आप कैसे') ||
      has('तुम कैसे')) {
    return VoiceCommand.howAreYou;
  }
  if (has('thank you') ||
      has('thanks') ||
      has('thank u') ||
      has('धन्यवाद') ||
      has('शुक्रिया') ||
      has('थैंक यू')) {
    return VoiceCommand.thanks;
  }
  if (has('good morning') ||
      has('good afternoon') ||
      has('good evening') ||
      has('hello cue') ||
      has('hey cue') ||
      exact('hello') ||
      exact('namaste') ||
      has('नमस्ते') ||
      exact('नमस्कार') ||
      has('सुप्रभात')) {
    return VoiceCommand.greeting;
  }

  // Vision questions. Checked before "what is this" so the words "what is"
  // cannot swallow them.
  if (has('what colour') ||
      has('what color') ||
      has('which colour') ||
      has('which color') ||
      has('what is the colour') ||
      has('what is the color') ||
      has("what's the colour") ||
      has("what's the color") ||
      has('colour of this') ||
      has('color of this') ||
      has('रंग क्या') ||
      has('क्या रंग') ||
      has('कौन सा रंग') ||
      has('इसका रंग') ||
      exact('रंग')) {
    return VoiceCommand.questionColour;
  }
  if (has('on my left') ||
      has('to my left') ||
      has('on the left') ||
      has('to the left') ||
      has('left side') ||
      has('मेरी बाईं ओर') ||
      has('मेरे बाईं ओर') ||
      has('बाईं ओर क्या') ||
      has('बाएँ क्या') ||
      has('बाईं तरफ')) {
    return VoiceCommand.whatIsLeft;
  }
  if (has('on my right') ||
      has('to my right') ||
      has('on the right') ||
      has('to the right') ||
      has('right side') ||
      has('मेरी दाईं ओर') ||
      has('मेरे दाईं ओर') ||
      has('दाईं ओर क्या') ||
      has('दाएँ क्या') ||
      has('दाईं तरफ')) {
    return VoiceCommand.whatIsRight;
  }

  // "What is this" is the most natural way to ask for a read or a description.
  // The screen decides which, because only it knows whether object mode is on.
  if (has('what is this') ||
      has('what s this') ||
      has('what is that') ||
      has('what s that') ||
      has('what do you see') ||
      has('what can you see') ||
      has('यह क्या') ||
      has('ये क्या') ||
      has('वह क्या') ||
      has('क्या दिख')) {
    return VoiceCommand.whatIsThis;
  }

  // State questions must beat the switch phrases: "is the torch on" contains
  // "torch on" and would otherwise turn the torch on instead of answering.
  if (has('is the torch on') ||
      has('is the torch off') ||
      has('is my torch on') ||
      has('is my torch off') ||
      has('is my light on') ||
      has('is my light off') ||
      has('torch is on') ||
      has('torch is off') ||
      has('is the light on') ||
      has('is the flashlight on') ||
      has('is the flashlight off') ||
      has('टॉर्च चालू है') ||
      has('टॉर्च ऑन है') ||
      has('टॉर्च बंद है') ||
      has('टॉर्च जल')) {
    return VoiceCommand.torchState;
  }

  if (has('how fast') ||
      has('what speed') ||
      has('reading speed') ||
      has('speech speed') ||
      has('how slow') ||
      has('कितनी तेज़') ||
      has('कितनी तेज') ||
      has('किस गति') ||
      has('पढ़ने की गति') ||
      has('गति क्या')) {
    return VoiceCommand.readingSpeed;
  }

  if (has('battery') ||
      has('charge level') ||
      has('how much charge') ||
      has('बैटरी') ||
      has('चार्ज')) {
    return VoiceCommand.battery;
  }

  // Torch is a device control, not a reading command.
  if (has('torch on') ||
      has('turn on the torch') ||
      has('turn on torch') ||
      has('light on') ||
      has('turn on the light') ||
      has('the light on') ||
      has('flashlight on') ||
      has('turn on the flashlight') ||
      has('switch on the torch') ||
      has('switch on light') ||
      has('टॉर्च चालू') ||
      has('टॉर्च ऑन') ||
      has('लाइट चालू') ||
      has('रोशनी चालू')) {
    return VoiceCommand.torchOn;
  }
  if (has('torch off') ||
      has('turn off the torch') ||
      has('turn off torch') ||
      has('light off') ||
      has('turn off the light') ||
      has('the light off') ||
      has('flashlight off') ||
      has('turn off the flashlight') ||
      has('switch off the torch') ||
      has('switch off light') ||
      has('टॉर्च बंद') ||
      has('टॉर्च ऑफ') ||
      has('लाइट बंद') ||
      has('रोशनी बंद')) {
    return VoiceCommand.torchOff;
  }

  // Questions about the phone itself. Checked before reading commands so
  // "what time is it" never becomes "read".
  if (has('what time') ||
      has('the time') ||
      has('time please') ||
      has('tell me the time') ||
      has('current time') ||
      has('time now') ||
      exact('time') ||
      has('समय क्या') ||
      has('क्या समय') ||
      has('टाइम क्या') ||
      has('अभी समय') ||
      has('समय बताओ') ||
      exact('समय') ||
      exact('टाइम')) {
    return VoiceCommand.currentTime;
  }
  if (has('what date') ||
      has('the date') ||
      has('date please') ||
      has('today s date') ||
      has('what day') ||
      has('which day') ||
      has('तारीख') ||
      has('तारीख क्या') ||
      has('कौन सा दिन') ||
      has('कौन सी तारीख') ||
      has('आज कौन') ||
      exact('date') ||
      exact('दिन')) {
    return VoiceCommand.currentDate;
  }
  // Where the reading got to. Must be checked before the fuzzy "where"
  // fallback to the location command.
  if (has('where was i') ||
      has('where were we') ||
      has('how much is left') ||
      has('how much left') ||
      has('how many sentences') ||
      has('how far did you') ||
      has('reading progress') ||
      has('कहाँ था') ||
      has('कहाँ थी') ||
      has('कितना बाकी') ||
      has('कितना बचा') ||
      has('कितने वाक्य')) {
    return VoiceCommand.readingProgress;
  }

  // "turn on location" is a request to fix the switch, not a question about
  // where the user is. Checked before the location questions.
  if (has('turn on location') ||
      has('turn location on') ||
      has('location on') ||
      has('enable location') ||
      has('location settings') ||
      has('open location settings') ||
      has('लोकेशन चालू') ||
      has('लोकेशन सेटिंग') ||
      has('स्थान चालू') ||
      exact('location settings')) {
    return VoiceCommand.locationSettings;
  }
  if (has('where am i') ||
      has('where are we') ||
      has('my location') ||
      has('current location') ||
      has('tell me my location') ||
      has('what is my location') ||
      has('which place') ||
      has('what place') ||
      has('मैं कहाँ') ||
      has('हम कहाँ') ||
      has('मेरी लोकेशन') ||
      has('कौन सी जगह') ||
      has('कहाँ हूँ') ||
      exact('location') ||
      exact('लोकेशन') ||
      exact('जगह')) {
    return VoiceCommand.location;
  }

  // "start over" must beat "start" (read now) and "फिर से" (repeat).
  if (has('start over') ||
      has('from the beginning') ||
      has('from the start') ||
      has('from the top') ||
      has('read from the top') ||
      has('restart') ||
      has('शुरू से') ||
      has('फिर से शुरू') ||
      has('पहले से') ||
      has('आरंभ से')) {
    return VoiceCommand.startOver;
  }

  // Navigation before repeat: "back" and "पिछला" are not repeat commands.
  if (has('next') ||
      has('next sentence') ||
      has('next line') ||
      has('forward') ||
      has('अगला') ||
      has('अगली') ||
      has('आगे')) {
    return VoiceCommand.nextSentence;
  }
  if (has('previous') ||
      has('previous sentence') ||
      has('go back') ||
      has('back') ||
      has('पिछला') ||
      has('पिछली') ||
      has('पीछे') ||
      has('वापस')) {
    return VoiceCommand.previousSentence;
  }

  // A question about the current mode, not a request to change it.
  if (has('what mode') ||
      has('which mode') ||
      has('mode am i in') ||
      has('mode are you in') ||
      has('current mode') ||
      has('कौन सा मोड') ||
      has('कौन मोड') ||
      has('मोड क्या है')) {
    return VoiceCommand.whatMode;
  }

  // Modes next. "screen" on its own is a mode, not "show preview".
  if (has('text mode') ||
      has('read mode') ||
      has('switch to text') ||
      has('पाठ मोड') ||
      has('टेक्स्ट मोड') ||
      exact('text') ||
      exact('पाठ') ||
      exact('टेक्स्ट')) {
    return VoiceCommand.textMode;
  }
  if (has('object mode') ||
      has('identify mode') ||
      has('switch to object') ||
      has('identify objects') ||
      has('identify object') ||
      has('describe objects') ||
      has('वस्तु मोड') ||
      has('ऑब्जेक्ट मोड') ||
      exact('object') ||
      exact('objects') ||
      exact('identify') ||
      exact('वस्तु') ||
      exact('ऑब्जेक्ट')) {
    return VoiceCommand.objectMode;
  }
  if (has('banknote mode') ||
      has('currency mode') ||
      has('switch to banknote') ||
      has('switch to currency') ||
      has('नोट मोड') ||
      has('करेंसी मोड') ||
      exact('banknote') ||
      exact('currency') ||
      exact('note') ||
      exact('नोट') ||
      exact('करेंसी')) {
    return VoiceCommand.banknoteMode;
  }
  if (has('screen mode') ||
      has('switch to screen') ||
      has('स्क्रीन मोड') ||
      exact('screen') ||
      exact('स्क्रीन')) {
    return VoiceCommand.screenMode;
  }

  // Repair: repeat the last answer, not the last page reading. Checked before
  // the general repeat phrases so "what did you say" is not treated as a page
  // command.
  if (has('what did you say') ||
      has('what did you just say') ||
      has('what was that') ||
      has('what did you tell me') ||
      has('come again') ||
      has('क्या कहा') ||
      has('क्या कहा आपने') ||
      has('क्या बोला')) {
    return VoiceCommand.repeatAnswer;
  }

  // "Never mind" cancels the request without pretending it succeeded.
  if (has('never mind') ||
      has('nevermind') ||
      has('forget it') ||
      has('forget about it') ||
      has('leave it') ||
      has('cancel') ||
      has('कुछ नहीं') ||
      has('रहने दो') ||
      has('छोड़ो') ||
      has('कैंसल')) {
    return VoiceCommand.neverMind;
  }

  // Repeat before read: "read again" asks for the last result, not a new scan.
  if (has('repeat') ||
      has('say again') ||
      has('say that again') ||
      has('read again') ||
      has('read it again') ||
      has('read that again') ||
      has('read it to me again') ||
      has('one more time') ||
      has('once more') ||
      has('दोहराओ') ||
      has('दोहरा') ||
      has('दोबारा') ||
      has('दुबारा') ||
      has('फिर से') ||
      has('फिरसे') ||
      exact('again') ||
      exact('फिर')) {
    return VoiceCommand.repeat;
  }

  if (has('stop') ||
      has('be quiet') ||
      has('quiet') ||
      has('silence') ||
      has('shut up') ||
      has('hush') ||
      has('enough') ||
      has('रुको') ||
      has('रुक') ||
      has('बंद करो') ||
      has('बंद') ||
      has('चुप') ||
      has('काफी है')) {
    return VoiceCommand.stop;
  }
  if (has('pause') ||
      has('wait') ||
      has('hold on') ||
      has('give me a second') ||
      has('ठहरो') ||
      has('ठहर') ||
      has('रुक जाओ')) {
    return VoiceCommand.pause;
  }
  if (has('resume') ||
      has('continue') ||
      has('go on') ||
      has('keep going') ||
      has('carry on') ||
      has('unpause') ||
      has('जारी रखो') ||
      has('जारी') ||
      has('चालू करो') ||
      has('चालू')) {
    return VoiceCommand.resume;
  }

  if (has('help') ||
      has('what can i say') ||
      has('what do i say') ||
      has('what can i do') ||
      has('what can you do') ||
      has('how do i use this') ||
      has('instructions') ||
      has('commands') ||
      has('what are the commands') ||
      has('मदद') ||
      has('सहायता') ||
      has('क्या कहूँ') ||
      has('क्या कह सकता हूँ') ||
      has('कमांड')) {
    return VoiceCommand.help;
  }
  if (has('slower') ||
      has('slow down') ||
      has('speak slower') ||
      has('too fast') ||
      has('धीरे') ||
      has('धीमा') ||
      has('धीरे बोलो') ||
      has('बहुत तेज़')) {
    return VoiceCommand.slower;
  }
  if (has('faster') ||
      has('speed up') ||
      has('speak faster') ||
      has('too slow') ||
      has('तेज़') ||
      has('तेज') ||
      has('जल्दी') ||
      has('तेज़ बोलो') ||
      has('बहुत धीमा')) {
    return VoiceCommand.faster;
  }
  if (has('show preview') ||
      has('show the preview') ||
      has('preview') ||
      has('show screen') ||
      has('दिखाओ') ||
      has('प्रीव्यू') ||
      has('पूर्वावलोकन') ||
      has('स्क्रीन दिखाओ')) {
    return VoiceCommand.showPreview;
  }

  if (has('read') ||
      has('scan') ||
      has('start reading') ||
      has('read it') ||
      has('read this') ||
      has('read that') ||
      has('read the page') ||
      has('what does it say') ||
      has('what does this say') ||
      has('what does that say') ||
      has('पढ़ो') ||
      has('पढ़') ||
      has('पढ़िए') ||
      has('पढ़ना') ||
      has('बोलो') ||
      has('सुनाओ') ||
      has('शुरू करो') ||
      exact('start') ||
      exact('begin') ||
      exact('look')) {
    return VoiceCommand.readNow;
  }

  // Near-misses. Speech recognisers turn "read" into "red", "reed" or "read
  // it", and a blind user gets no second chance to see what went wrong. Only
  // short utterances are fuzzed, so a long sentence cannot accidentally match.
  if (text.split(' ').length <= 3) {
    if (near('read')) return VoiceCommand.readNow;
    if (near('repeat')) return VoiceCommand.repeat;
    if (near('stop')) return VoiceCommand.stop;
    if (near('pause')) return VoiceCommand.pause;
    if (near('resume')) return VoiceCommand.resume;
    if (near('next')) return VoiceCommand.nextSentence;
    if (near('back') || near('previous')) return VoiceCommand.previousSentence;
    if (near('help')) return VoiceCommand.help;
    if (near('time')) return VoiceCommand.currentTime;
    if (near('date')) return VoiceCommand.currentDate;
    if (near('location') || near('where')) return VoiceCommand.location;
    if (near('slower')) return VoiceCommand.slower;
    if (near('faster')) return VoiceCommand.faster;
  }

  return VoiceCommand.unknown;
}

/// True when one word of a short transcript is one edit away from [word].
///
/// Used only for single-word commands: at that length a one-letter difference
/// is almost always the recogniser, not a different intention.
bool _near(String text, String word) {
  final clean = word;
  if (clean.length < 4) return false;

  for (final token in text.split(' ')) {
    if (token.length < 3) continue;
    if ((token.length - clean.length).abs() > 1) continue;
    if (_editDistance(token, clean) <= 1) return true;
  }
  return false;
}

/// Levenshtein distance, capped at 2 for speed: any larger difference is not a
/// match anyway.
int _editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (index) => index);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final deletion = previous[j] + 1;
      final insertion = current[j - 1] + 1;
      final substitution = previous[j - 1] + cost;
      var best = deletion < insertion ? deletion : insertion;
      if (substitution < best) best = substitution;
      current[j] = best;
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

/// Lowercases, strips punctuation and collapses whitespace.
///
/// Unicode-aware on purpose: Devanagari letters, vowel signs and nukta marks
/// must survive normalisation, or every Hindi command becomes an empty string.
///
/// The nukta (U+093C) is dropped after normalisation. Speech recognisers and
/// OCR disagree about it constantly — the same command arrives as "पढ़ो" from
/// one engine and "पढो" from another — and the difference is not meaningful
/// for a command word.
String _normalize(String raw) {
  final lower = raw.toLowerCase();
  final words = lower.replaceAll(
    RegExp(r'[^\p{L}\p{M}\p{N}\u200C\u200D ]+', unicode: true),
    ' ',
  );
  return words.replaceAll('\u093C', '').replaceAll(RegExp(r'\s+'), ' ').trim();
}
