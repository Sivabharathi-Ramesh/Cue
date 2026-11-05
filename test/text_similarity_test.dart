import 'package:cue/core/text_similarity.dart';
import 'package:cue/live/stability_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeText', () {
    test('lowercases, strips punctuation and collapses whitespace', () {
      expect(
        normalizeText('  Hello,   WORLD!\nSecond line. '),
        'hello world second line',
      );
    });

    test('keeps Devanagari letters and marks', () {
      expect(normalizeText('  यह, एक वाक्य है। '), 'यह एक वाक्य है');
      expect(normalizeText('कीमत ₹५०० है'), 'कीमत ५०० है');
    });
  });

  group('tokenJaccard', () {
    test('near-identical OCR frames score high', () {
      final score = tokenJaccard(
        'the quick brown fox jumps over the lazy dog',
        'the quick brown fox jumped over a lazy dog',
      );
      expect(score, greaterThan(0.6));
    });

    test('different pages score low', () {
      final score = tokenJaccard(
        'bank statement due date total',
        'paracetamol 500 mg expiry',
      );
      expect(score, lessThan(0.1));
    });
  });

  group('newTokenRatio', () {
    test('the same page is not new', () {
      expect(
        newTokenRatio('turn left at the sign', 'turn left at the sign'),
        0,
      );
    });

    test('a different page is entirely new', () {
      expect(newTokenRatio('turn left at the sign', 'danger high voltage'), 1);
    });

    test('a mostly new page clears the speak threshold', () {
      expect(
        newTokenRatio(
          'chapter one the beginning',
          'chapter two the middle of the story',
        ),
        greaterThan(0.35),
      );
    });
  });

  group('Hindi text comparison', () {
    test('near-identical Hindi frames score high', () {
      final score = tokenJaccard(
        'यह पेज हिंदी में लिखा है',
        'यह पेज हिंदी में लिखा हुआ है',
      );
      expect(score, greaterThan(0.6));
    });

    test('a different Hindi page clears the speak threshold', () {
      expect(
        newTokenRatio('बिल की कुल राशि', 'दवा की अंतिम तारीख'),
        greaterThan(0.35),
      );
    });
  });

  group('charBigramSimilarity', () {
    test('survives OCR changing a number to a word', () {
      final score = charBigramSimilarity(
        'Platform nine and three quarters',
        'Platform 9 and three quarters',
      );
      expect(score, greaterThan(0.8));
    });

    test('two different pages score low', () {
      final score = charBigramSimilarity(
        'bank statement due date total',
        'paracetamol 500 mg expiry',
      );
      expect(score, lessThan(0.4));
    });
  });

  group('StabilityGate', () {
    test('needs two frames before the text is trusted', () {
      final gate = StabilityGate();
      expect(gate.add('Platform nine and three quarters'), isFalse);
      expect(gate.add('Platform nine and three quarters'), isTrue);
    });

    test('an OCR jitter does not need a fresh confirmation', () {
      final gate = StabilityGate();
      gate.add('Platform nine and three quarters');
      expect(gate.add('Platform 9 and three quarters'), isTrue);
    });

    test('a new page starts its own confirmation', () {
      final gate = StabilityGate();
      gate.add('First page text');
      expect(gate.add('First page text'), isTrue);
      expect(gate.add('Completely different second page'), isFalse);
      expect(gate.add('Completely different second page'), isTrue);
    });

    test('a single character is not a reading', () {
      final gate = StabilityGate();
      expect(gate.add('A'), isFalse);
      expect(gate.add('A'), isFalse);
    });

    test('reset forgets the candidate', () {
      final gate = StabilityGate();
      gate.add('Some text');
      gate.add('Some text');
      gate.reset();
      expect(gate.add('Some text'), isFalse);
    });
  });
}
