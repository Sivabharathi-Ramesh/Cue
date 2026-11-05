import 'package:cue/core/sentence_splitter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitSentences', () {
    test('splits English sentences and keeps their punctuation', () {
      expect(
        splitSentences('The bill is due. Please pay it today! Is that clear?'),
        <String>['The bill is due.', 'Please pay it today!', 'Is that clear?'],
      );
    });

    test('splits Hindi on the danda and double danda', () {
      expect(
        splitSentences('यह पहला वाक्य है। यह दूसरा है॥ और तीसरा?'),
        <String>['यह पहला वाक्य है।', 'यह दूसरा है॥', 'और तीसरा?'],
      );
    });

    test('a danda without a following space still splits', () {
      expect(splitSentences('पहला।दूसरा।'), <String>['पहला।', 'दूसरा।']);
    });

    test('a decimal point is not a sentence break', () {
      expect(splitSentences('The total is 42.50 today.'), <String>[
        'The total is 42.50 today.',
      ]);
    });

    test('common abbreviations stay attached to the next sentence', () {
      expect(splitSentences('Dr. Rao arrived. He was late.'), <String>[
        'Dr. Rao arrived.',
        'He was late.',
      ]);
      expect(splitSentences('See No. 5 for details. Thank you.'), <String>[
        'See No. 5 for details.',
        'Thank you.',
      ]);
    });

    test('long sentences are cut at a comma or space', () {
      final long = 'This is a very long line, ${'word ' * 80}and the end.';
      final pieces = splitSentences(long, maxLength: 80);
      expect(pieces.length, greaterThan(1));
      for (final piece in pieces) {
        expect(piece.length, lessThanOrEqualTo(90));
        expect(piece, isNotEmpty);
      }
    });

    test('empty and punctuation-only text has no sentences', () {
      expect(splitSentences(''), isEmpty);
      expect(splitSentences('   '), isEmpty);
      expect(splitSentences('... !!!'), isEmpty);
    });

    test('newlines are treated as spaces, not as a crash', () {
      expect(splitSentences('First line.\nSecond line.'), <String>[
        'First line.',
        'Second line.',
      ]);
    });
  });
}
