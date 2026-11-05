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

  // "start over" must beat "start" (read now) and "फिर से" (repeat).
  if (has('start over') ||
      has('from the beginning') ||
      has('from the start') ||
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
      has('वस्तु मोड') ||
      has('ऑब्जेक्ट मोड') ||
      exact('object') ||
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

  // Repeat before read: "read again" asks for the last result, not a new scan.
  if (has('repeat') ||
      has('say again') ||
      has('say that again') ||
      has('read again') ||
      has('read that again') ||
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

  return VoiceCommand.unknown;
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
