import 'package:cue/core/voice_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reading commands', () {
    test('read, scan and read now', () {
      expect(parseVoiceCommand('read'), VoiceCommand.readNow);
      expect(parseVoiceCommand('Read now.'), VoiceCommand.readNow);
      expect(parseVoiceCommand('scan this page'), VoiceCommand.readNow);
      expect(
        parseVoiceCommand('can you read this for me'),
        VoiceCommand.readNow,
      );
      expect(parseVoiceCommand('what does it say'), VoiceCommand.readNow);
      expect(parseVoiceCommand('start'), VoiceCommand.readNow);
      expect(parseVoiceCommand('begin'), VoiceCommand.readNow);
      expect(parseVoiceCommand('look'), VoiceCommand.readNow);
    });

    test('repeat beats read in "read again"', () {
      expect(parseVoiceCommand('repeat'), VoiceCommand.repeat);
      expect(parseVoiceCommand('say that again'), VoiceCommand.repeat);
      expect(parseVoiceCommand('read again'), VoiceCommand.repeat);
      expect(parseVoiceCommand('one more time'), VoiceCommand.repeat);
      expect(parseVoiceCommand('once more'), VoiceCommand.repeat);
      expect(parseVoiceCommand('again'), VoiceCommand.repeat);
    });

    test('stop and its polite variants', () {
      expect(parseVoiceCommand('stop'), VoiceCommand.stop);
      expect(parseVoiceCommand('Stop reading!'), VoiceCommand.stop);
      expect(parseVoiceCommand('be quiet'), VoiceCommand.stop);
      expect(parseVoiceCommand('quiet'), VoiceCommand.stop);
      expect(parseVoiceCommand('silence'), VoiceCommand.stop);
      expect(parseVoiceCommand("that's enough"), VoiceCommand.stop);
    });

    test('pause and resume', () {
      expect(parseVoiceCommand('pause'), VoiceCommand.pause);
      expect(parseVoiceCommand('wait'), VoiceCommand.pause);
      expect(parseVoiceCommand('hold on'), VoiceCommand.pause);
      expect(parseVoiceCommand('give me a second'), VoiceCommand.pause);
      expect(parseVoiceCommand('resume'), VoiceCommand.resume);
      expect(parseVoiceCommand('continue'), VoiceCommand.resume);
      expect(parseVoiceCommand('go on'), VoiceCommand.resume);
      expect(parseVoiceCommand('keep going'), VoiceCommand.resume);
      expect(parseVoiceCommand('carry on'), VoiceCommand.resume);
      expect(parseVoiceCommand('unpause'), VoiceCommand.resume);
    });
  });

  group('settings commands', () {
    test('help', () {
      expect(parseVoiceCommand('help'), VoiceCommand.help);
      expect(parseVoiceCommand('what can I say?'), VoiceCommand.help);
      expect(parseVoiceCommand('what do I say'), VoiceCommand.help);
      expect(parseVoiceCommand('what can I do'), VoiceCommand.help);
      expect(parseVoiceCommand('commands'), VoiceCommand.help);
    });

    test('speech speed', () {
      expect(parseVoiceCommand('slower'), VoiceCommand.slower);
      expect(parseVoiceCommand('slow down'), VoiceCommand.slower);
      expect(parseVoiceCommand('speak slower'), VoiceCommand.slower);
      expect(parseVoiceCommand('too fast'), VoiceCommand.slower);
      expect(parseVoiceCommand('faster'), VoiceCommand.faster);
      expect(parseVoiceCommand('speed up'), VoiceCommand.faster);
      expect(parseVoiceCommand('speak faster'), VoiceCommand.faster);
      expect(parseVoiceCommand('too slow'), VoiceCommand.faster);
    });

    test('preview', () {
      expect(parseVoiceCommand('show preview'), VoiceCommand.showPreview);
      expect(parseVoiceCommand('show the preview'), VoiceCommand.showPreview);
      expect(parseVoiceCommand('preview'), VoiceCommand.showPreview);
    });
  });

  group('mode commands', () {
    test('text mode', () {
      expect(parseVoiceCommand('text mode'), VoiceCommand.textMode);
      expect(parseVoiceCommand('Read mode'), VoiceCommand.textMode);
      expect(parseVoiceCommand('switch to text'), VoiceCommand.textMode);
      expect(parseVoiceCommand('text'), VoiceCommand.textMode);
    });

    test('object mode', () {
      expect(parseVoiceCommand('object mode'), VoiceCommand.objectMode);
      expect(parseVoiceCommand('identify mode'), VoiceCommand.objectMode);
      expect(parseVoiceCommand('identify'), VoiceCommand.objectMode);
    });

    test('banknote mode', () {
      expect(parseVoiceCommand('banknote mode'), VoiceCommand.banknoteMode);
      expect(parseVoiceCommand('currency mode'), VoiceCommand.banknoteMode);
      expect(parseVoiceCommand('note'), VoiceCommand.banknoteMode);
    });

    test('screen mode is a mode, not a preview', () {
      expect(parseVoiceCommand('screen mode'), VoiceCommand.screenMode);
      expect(parseVoiceCommand('screen'), VoiceCommand.screenMode);
    });
  });

  group('reading navigation', () {
    test('English next, back and start over', () {
      expect(parseVoiceCommand('next'), VoiceCommand.nextSentence);
      expect(parseVoiceCommand('next sentence'), VoiceCommand.nextSentence);
      expect(parseVoiceCommand('previous'), VoiceCommand.previousSentence);
      expect(parseVoiceCommand('go back'), VoiceCommand.previousSentence);
      expect(parseVoiceCommand('back'), VoiceCommand.previousSentence);
      expect(parseVoiceCommand('start over'), VoiceCommand.startOver);
      expect(parseVoiceCommand('from the beginning'), VoiceCommand.startOver);
      expect(parseVoiceCommand('restart'), VoiceCommand.startOver);
    });

    test('start over beats repeat in "फिर से शुरू"', () {
      expect(parseVoiceCommand('फिर से शुरू'), VoiceCommand.startOver);
      expect(parseVoiceCommand('शुरू से'), VoiceCommand.startOver);
      expect(parseVoiceCommand('फिर से'), VoiceCommand.repeat);
    });
  });

  group('Hindi commands', () {
    test('reading and stopping', () {
      expect(parseVoiceCommand('पढ़ो'), VoiceCommand.readNow);
      expect(parseVoiceCommand('पढ़िए'), VoiceCommand.readNow);
      expect(parseVoiceCommand('रुको'), VoiceCommand.stop);
      expect(parseVoiceCommand('बंद करो'), VoiceCommand.stop);
      expect(parseVoiceCommand('चुप'), VoiceCommand.stop);
    });

    test('navigation', () {
      expect(parseVoiceCommand('अगला'), VoiceCommand.nextSentence);
      expect(parseVoiceCommand('अगली'), VoiceCommand.nextSentence);
      expect(parseVoiceCommand('पिछला'), VoiceCommand.previousSentence);
      expect(parseVoiceCommand('वापस'), VoiceCommand.previousSentence);
    });

    test('repeat and pause', () {
      expect(parseVoiceCommand('दोहराओ'), VoiceCommand.repeat);
      expect(parseVoiceCommand('दोबारा'), VoiceCommand.repeat);
      expect(parseVoiceCommand('ठहरो'), VoiceCommand.pause);
      expect(parseVoiceCommand('जारी रखो'), VoiceCommand.resume);
      expect(parseVoiceCommand('चालू करो'), VoiceCommand.resume);
    });

    test('help and speed', () {
      expect(parseVoiceCommand('मदद'), VoiceCommand.help);
      expect(parseVoiceCommand('सहायता'), VoiceCommand.help);
      expect(parseVoiceCommand('धीरे'), VoiceCommand.slower);
      expect(parseVoiceCommand('तेज़'), VoiceCommand.faster);
      expect(parseVoiceCommand('तेज'), VoiceCommand.faster);
    });

    test('torch controls', () {
      expect(parseVoiceCommand('torch on'), VoiceCommand.torchOn);
      expect(parseVoiceCommand('turn on the torch'), VoiceCommand.torchOn);
      expect(parseVoiceCommand('light off'), VoiceCommand.torchOff);
      expect(parseVoiceCommand('वॉल्यूम'), VoiceCommand.unknown);
      expect(parseVoiceCommand('टॉर्च बंद'), VoiceCommand.torchOff);
      expect(parseVoiceCommand('लाइट बंद'), VoiceCommand.torchOff);
      expect(parseVoiceCommand('टॉर्च चालू'), VoiceCommand.torchOn);
    });

    test('language switching', () {
      expect(parseVoiceCommand('हिंदी'), VoiceCommand.hindiMode);
      expect(parseVoiceCommand('हिन्दी'), VoiceCommand.hindiMode);
      expect(parseVoiceCommand('अंग्रेज़ी'), VoiceCommand.englishMode);
      expect(parseVoiceCommand('अंग्रेजी'), VoiceCommand.englishMode);
      expect(parseVoiceCommand('english'), VoiceCommand.englishMode);
    });

    test('Devanagari survives normalisation', () {
      expect(parseVoiceCommand('  पढ़ो!!!  '), VoiceCommand.readNow);
      expect(parseVoiceCommand('“रुको।”'), VoiceCommand.stop);
    });

    test('a missing nukta does not change the command', () {
      // Recognisers write the same word both ways.
      expect(parseVoiceCommand('पढो'), VoiceCommand.readNow);
      expect(parseVoiceCommand('पढिए'), VoiceCommand.readNow);
      expect(parseVoiceCommand('अंग्रेजी'), VoiceCommand.englishMode);
      expect(parseVoiceCommand('तेज'), VoiceCommand.faster);
    });

    test('an ordinary Hindi sentence is unknown', () {
      expect(parseVoiceCommand('आज मौसम बहुत अच्छा है'), VoiceCommand.unknown);
    });
  });

  group('normalisation', () {
    test('case, punctuation and extra spaces do not matter', () {
      expect(parseVoiceCommand('  READ!!!  '), VoiceCommand.readNow);
      expect(parseVoiceCommand('Show   Preview.'), VoiceCommand.showPreview);
      expect(parseVoiceCommand('\u201cStop.\u201d'), VoiceCommand.stop);
    });

    test('empty and irrelevant speech is unknown', () {
      expect(parseVoiceCommand(''), VoiceCommand.unknown);
      expect(parseVoiceCommand('   '), VoiceCommand.unknown);
      expect(parseVoiceCommand('what is the weather'), VoiceCommand.unknown);
      expect(parseVoiceCommand('the quick brown fox'), VoiceCommand.unknown);
    });

    test('words are matched whole, not inside other words', () {
      expect(parseVoiceCommand('reading'), VoiceCommand.unknown);
      expect(parseVoiceCommand('unread'), VoiceCommand.unknown);
    });
  });

  group('phone facts', () {
    test('time questions', () {
      expect(parseVoiceCommand('what time is it'), VoiceCommand.currentTime);
      expect(parseVoiceCommand('what is the time'), VoiceCommand.currentTime);
      expect(parseVoiceCommand('tell me the time'), VoiceCommand.currentTime);
      expect(parseVoiceCommand('time'), VoiceCommand.currentTime);
      expect(parseVoiceCommand('समय क्या है'), VoiceCommand.currentTime);
      expect(parseVoiceCommand('टाइम क्या है'), VoiceCommand.currentTime);
    });

    test('date questions', () {
      expect(parseVoiceCommand("what's the date"), VoiceCommand.currentDate);
      expect(parseVoiceCommand('today\'s date'), VoiceCommand.currentDate);
      expect(parseVoiceCommand('which day is it'), VoiceCommand.currentDate);
      expect(parseVoiceCommand('तारीख क्या है'), VoiceCommand.currentDate);
    });

    test('location questions', () {
      expect(parseVoiceCommand('where am I'), VoiceCommand.location);
      expect(parseVoiceCommand('where are we'), VoiceCommand.location);
      expect(parseVoiceCommand('what is my location'), VoiceCommand.location);
      expect(parseVoiceCommand('मैं कहाँ हूँ'), VoiceCommand.location);
      expect(parseVoiceCommand('मेरी लोकेशन'), VoiceCommand.location);
    });

    test('turning location on is its own command', () {
      expect(
        parseVoiceCommand('turn on location'),
        VoiceCommand.locationSettings,
      );
      expect(
        parseVoiceCommand('open location settings'),
        VoiceCommand.locationSettings,
      );
      expect(
        parseVoiceCommand('लोकेशन चालू करो'),
        VoiceCommand.locationSettings,
      );
    });

    test('time is not confused with reading', () {
      expect(parseVoiceCommand('read this page'), VoiceCommand.readNow);
      expect(parseVoiceCommand('what does it say'), VoiceCommand.readNow);
    });
  });

  group('natural questions', () {
    test('name and identity', () {
      expect(parseVoiceCommand('what is your name'), VoiceCommand.whoAreYou);
      expect(parseVoiceCommand("what's your name?"), VoiceCommand.whoAreYou);
      expect(parseVoiceCommand('who are you'), VoiceCommand.whoAreYou);
      expect(parseVoiceCommand('तुम्हारा नाम क्या है'), VoiceCommand.whoAreYou);
    });

    test('small talk is answered instead of rejected', () {
      expect(parseVoiceCommand('how are you'), VoiceCommand.howAreYou);
      expect(parseVoiceCommand('thank you'), VoiceCommand.thanks);
      expect(parseVoiceCommand('धन्यवाद'), VoiceCommand.thanks);
      expect(parseVoiceCommand('good morning'), VoiceCommand.greeting);
      expect(parseVoiceCommand('नमस्ते'), VoiceCommand.greeting);
    });

    test('what is this asks for a read or a description', () {
      expect(parseVoiceCommand('what is this'), VoiceCommand.whatIsThis);
      expect(parseVoiceCommand("what's that?"), VoiceCommand.whatIsThis);
      expect(parseVoiceCommand('what do you see'), VoiceCommand.whatIsThis);
      expect(parseVoiceCommand('यह क्या है'), VoiceCommand.whatIsThis);
    });

    test('a bare language request toggles, a named one does not', () {
      expect(parseVoiceCommand('change language'), VoiceCommand.toggleLanguage);
      expect(parseVoiceCommand('switch language'), VoiceCommand.toggleLanguage);
      expect(parseVoiceCommand('भाषा बदलो'), VoiceCommand.toggleLanguage);
      expect(
        parseVoiceCommand('change language to Hindi'),
        VoiceCommand.hindiMode,
      );
      expect(
        parseVoiceCommand('switch language to English'),
        VoiceCommand.englishMode,
      );
    });
  });

  group('state and repair questions', () {
    test('asking about the mode does not change it', () {
      expect(parseVoiceCommand('what mode am I in'), VoiceCommand.whatMode);
      expect(parseVoiceCommand('which mode is this'), VoiceCommand.whatMode);
      expect(parseVoiceCommand('कौन सा मोड है'), VoiceCommand.whatMode);
      expect(parseVoiceCommand('object mode'), VoiceCommand.objectMode);
    });

    test('asking about the language does not change it', () {
      expect(
        parseVoiceCommand('what language are you using'),
        VoiceCommand.whichLanguage,
      );
      expect(
        parseVoiceCommand('which language is this'),
        VoiceCommand.whichLanguage,
      );
      expect(parseVoiceCommand('कौन सी भाषा है'), VoiceCommand.whichLanguage);
      expect(parseVoiceCommand('hindi'), VoiceCommand.hindiMode);
    });

    test('is the torch on is a question, not a command', () {
      expect(parseVoiceCommand('is the torch on'), VoiceCommand.torchState);
      expect(parseVoiceCommand('is the light on'), VoiceCommand.torchState);
      expect(parseVoiceCommand('is my torch off'), VoiceCommand.torchState);
      expect(parseVoiceCommand('टॉर्च चालू है'), VoiceCommand.torchState);
      expect(parseVoiceCommand('turn on the torch'), VoiceCommand.torchOn);
      expect(parseVoiceCommand('turn off the light'), VoiceCommand.torchOff);
    });

    test('speed and battery questions', () {
      expect(
        parseVoiceCommand('how fast are you reading'),
        VoiceCommand.readingSpeed,
      );
      expect(
        parseVoiceCommand('what speed is this'),
        VoiceCommand.readingSpeed,
      );
      expect(parseVoiceCommand('कितनी तेज़ है'), VoiceCommand.readingSpeed);
      expect(parseVoiceCommand('battery'), VoiceCommand.battery);
      expect(
        parseVoiceCommand('how much charge is left'),
        VoiceCommand.battery,
      );
      expect(parseVoiceCommand('बैटरी'), VoiceCommand.battery);
      expect(parseVoiceCommand('faster'), VoiceCommand.faster);
    });

    test('conversation repair', () {
      expect(parseVoiceCommand('what did you say'), VoiceCommand.repeatAnswer);
      expect(
        parseVoiceCommand('what did you just say'),
        VoiceCommand.repeatAnswer,
      );
      expect(parseVoiceCommand('क्या कहा'), VoiceCommand.repeatAnswer);
      expect(parseVoiceCommand('never mind'), VoiceCommand.neverMind);
      expect(parseVoiceCommand('forget it'), VoiceCommand.neverMind);
      expect(parseVoiceCommand('cancel'), VoiceCommand.neverMind);
      expect(parseVoiceCommand('कुछ नहीं'), VoiceCommand.neverMind);
      expect(parseVoiceCommand('repeat'), VoiceCommand.repeat);
    });

    test('reading progress is not a location question', () {
      expect(parseVoiceCommand('where was I'), VoiceCommand.readingProgress);
      expect(
        parseVoiceCommand('how much is left'),
        VoiceCommand.readingProgress,
      );
      expect(
        parseVoiceCommand('how many sentences are left'),
        VoiceCommand.readingProgress,
      );
      expect(parseVoiceCommand('कहाँ था'), VoiceCommand.readingProgress);
      expect(parseVoiceCommand('where am I'), VoiceCommand.location);
      expect(parseVoiceCommand('read from the top'), VoiceCommand.startOver);
    });
  });

  group('vision questions', () {
    test('colour questions', () {
      expect(
        parseVoiceCommand('what colour is this'),
        VoiceCommand.questionColour,
      );
      expect(
        parseVoiceCommand('what color is it'),
        VoiceCommand.questionColour,
      );
      expect(parseVoiceCommand('which colour'), VoiceCommand.questionColour);
      expect(parseVoiceCommand('रंग क्या है'), VoiceCommand.questionColour);
      expect(parseVoiceCommand('what is this'), VoiceCommand.whatIsThis);
    });

    test('left and right questions', () {
      expect(parseVoiceCommand("what's on my left"), VoiceCommand.whatIsLeft);
      expect(parseVoiceCommand('what is on my left'), VoiceCommand.whatIsLeft);
      expect(
        parseVoiceCommand('anything on the left'),
        VoiceCommand.whatIsLeft,
      );
      expect(
        parseVoiceCommand('मेरी बाईं ओर क्या है'),
        VoiceCommand.whatIsLeft,
      );
      expect(parseVoiceCommand("what's on my right"), VoiceCommand.whatIsRight);
      expect(
        parseVoiceCommand('what is on my right'),
        VoiceCommand.whatIsRight,
      );
      expect(parseVoiceCommand('दाईं ओर क्या है'), VoiceCommand.whatIsRight);
    });
  });

  group('near-miss recognition', () {
    test('a one-letter slip still reads', () {
      expect(parseVoiceCommand('red'), VoiceCommand.readNow);
      expect(parseVoiceCommand('reed'), VoiceCommand.readNow);
    });

    test('a one-letter slip still repeats', () {
      expect(parseVoiceCommand('repead'), VoiceCommand.repeat);
      expect(parseVoiceCommand('repet'), VoiceCommand.repeat);
    });

    test('a one-letter slip still stops', () {
      expect(parseVoiceCommand('stp'), VoiceCommand.stop);
      expect(parseVoiceCommand('stopp'), VoiceCommand.stop);
    });

    test('a long sentence is never fuzzed into a command', () {
      expect(
        parseVoiceCommand('I was reading the newspaper on the red chair'),
        VoiceCommand.unknown,
      );
      expect(
        parseVoiceCommand('the road was wet and the light was dim'),
        VoiceCommand.unknown,
      );
    });
  });
}
