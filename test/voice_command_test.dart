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
      expect(parseVoiceCommand('stopwatch'), VoiceCommand.unknown);
      expect(parseVoiceCommand('reading'), VoiceCommand.unknown);
      expect(parseVoiceCommand('unread'), VoiceCommand.unknown);
    });
  });
}
