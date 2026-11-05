import 'package:cue/live/reading_quality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('printed text is read normally', () {
    test('a normal paragraph', () {
      const page =
          'The quick brown fox jumps over the lazy dog. '
          'It was a warm afternoon, and the road was quiet.';
      final quality = ReadingQuality.of(page, 0.91);
      expect(quality.tier, ReadingTier.certain);
      expect(quality.reason, isNull);
    });

    test('a receipt of numbers and short labels', () {
      const receipt = 'TOTAL 42.50 GBP\nVAT 8.50\nCARD 1234\nTHANK YOU';
      expect(looksLikeText(receipt), isTrue);
    });

    test('a short all-caps sign', () {
      expect(looksLikeText('EXIT'), isTrue);
      expect(looksLikeText('PUSH'), isTrue);
    });

    test('an acronym with no vowel is still a word', () {
      expect(looksLikeText('BBC NEWS'), isTrue);
      expect(looksLikeText('HRT clinic'), isTrue);
    });

    test('ordinary punctuation and apostrophes', () {
      expect(
        looksLikeText("Don\u2019t stop: it's 50% off (today only)."),
        isTrue,
      );
      expect(
        looksLikeText('\u201cWait\u201d \u2014 she said \u201cno\u201d\u2026'),
        isTrue,
      );
    });

    test('low confidence is spoken only with doubt first', () {
      final quality = ReadingQuality.of('The quick brown fox', 0.41);
      expect(quality.plausible, isTrue);
      expect(quality.speakable, isFalse);
      expect(quality.tier, ReadingTier.refused);

      final doubtful = ReadingQuality.of('The quick brown fox', 0.68);
      expect(doubtful.plausible, isTrue);
      expect(doubtful.speakable, isTrue);
      expect(doubtful.tier, ReadingTier.uncertain);
      expect(doubtful.reason, 'low confidence');
    });

    test('missing confidence falls back to the structural check', () {
      final quality = ReadingQuality.of('The quick brown fox', null);
      expect(quality.tier, ReadingTier.uncertain);
    });

    test('the calibrated printed-page reading is certain', () {
      const page =
          'E TEST PAG quick brown fox jump azy dog. This page is '
          'eck that Cue reads p correctly on a phone';
      expect(ReadingQuality.of(page, 0.82).tier, ReadingTier.certain);
    });
  });

  group('uncertain or refused readings are handled honestly', () {
    test('the calibrated cursive reading is spoken only with doubt', () {
      // ML Kit's own output for a handwritten page during calibration. It is
      // word-shaped, which is why structure alone cannot catch it, and its
      // mean confidence was 0.68.
      const cursive =
          'Sam, hg tomorrow at noon i room by the stairs. Pr the '
          'blve folder and the e back door. I will cal I get there. ks,';
      final quality = ReadingQuality.of(cursive, 0.68);
      expect(quality.plausible, isTrue);
      expect(quality.speakable, isTrue);
      expect(quality.tier, ReadingTier.uncertain);
      expect(quality.reason, 'low confidence');
    });

    test('a reading too uncertain even for doubt is refused', () {
      final quality = ReadingQuality.of(
        'Sam, hg tomorrow at noon i room by the stairs',
        0.29,
      );
      expect(quality.plausible, isTrue);
      expect(quality.speakable, isFalse);
      expect(quality.tier, ReadingTier.refused);
      expect(quality.reason, 'confidence too low');
    });
    test('symbol soup', () {
      expect(looksLikeText('@@@ ### \$\$\$ %%% ^^^ &&& ***'), isFalse);
      expect(looksLikeText('«»¶§±×÷'), isFalse);
    });

    test('consonant runs, the usual handwriting noise', () {
      expect(looksLikeText('rnln fflrt qwrtpsdfg bcdf'), isFalse);
    });

    test('a page of one- and two-character fragments', () {
      expect(looksLikeText('ab cd ef gh ij kl mn op'), isFalse);
    });

    test('one enormous unbroken token', () {
      expect(looksLikeText('abcdefghijklmnopqrstuvwxy'), isFalse);
    });

    test('a recognition loop of one repeated character', () {
      expect(looksLikeText('aaaaaaa aaaaaaa aaaaaaa'), isFalse);
    });

    test('a single character is not a reading', () {
      final quality = ReadingQuality.of('A', 0.99);
      expect(quality.tier, ReadingTier.refused);
      expect(quality.reason, 'too short');
    });

    test('the confidence boundaries', () {
      expect(
        ReadingQuality.of('The quick brown fox', minTrustedConfidence).tier,
        ReadingTier.certain,
      );
      expect(
        ReadingQuality.of(
          'The quick brown fox',
          minTrustedConfidence - 0.01,
        ).tier,
        ReadingTier.uncertain,
      );
      expect(
        ReadingQuality.of('The quick brown fox', minUncertainConfidence).tier,
        ReadingTier.uncertain,
      );
      expect(
        ReadingQuality.of(
          'The quick brown fox',
          minUncertainConfidence - 0.01,
        ).tier,
        ReadingTier.refused,
      );
    });
  });

  group('Hindi text is read like text', () {
    test('a normal Devanagari sentence is word-shaped', () {
      expect(looksLikeText('यह एक हिंदी वाक्य है।'), isTrue);
      expect(looksLikeText('कीमत ५०० रुपये है'), isTrue);
    });

    test('confidence applies to Hindi the same way', () {
      final certain = ReadingQuality.of('यह एक हिंदी वाक्य है।', 0.91);
      expect(certain.tier, ReadingTier.certain);
      final doubtful = ReadingQuality.of('यह एक हिंदी वाक्य है।', 0.68);
      expect(doubtful.tier, ReadingTier.uncertain);
    });

    test('Devanagari punctuation is not symbol soup', () {
      expect(looksLikeText('हाँ। ठीक है॥'), isTrue);
    });

    test('real symbol soup is still refused', () {
      expect(looksLikeText('॥॥ ॥॥ ॥॥'), isFalse);
    });
  });

  test('the debug description carries the tier and confidence', () {
    final quality = ReadingQuality.of('The quick brown fox', 0.83);
    expect(quality.toString(), contains('0.83'));
    expect(quality.toString(), contains('tier certain'));
  });
}
