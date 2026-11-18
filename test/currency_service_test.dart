import 'package:cue/core/cue_language.dart';
import 'package:cue/core/cue_strings.dart';
import 'package:cue/vision/currency_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('analyseBanknoteText', () {
    test('a repeated value with the RBI banner is strong', () {
      final reading = analyseBanknoteText('''
RESERVE BANK OF INDIA
500
GUARANTEED BY THE CENTRAL GOVERNMENT
500
''');
      expect(reading.rupees, 500);
      expect(reading.evidence, BanknoteEvidence.strong);
      expect(reading.problem, BanknoteProblem.none);
    });

    test('a repeated value without the banner needs a second frame', () {
      final reading = analyseBanknoteText('500 500');
      expect(reading.rupees, 500);
      expect(reading.evidence, BanknoteEvidence.medium);
    });

    test('one numeral plus the banner is plausible but not strong', () {
      final reading = analyseBanknoteText('RESERVE BANK OF INDIA 500');
      expect(reading.rupees, 500);
      expect(reading.evidence, BanknoteEvidence.medium);
    });

    test('a single numeral is a candidate, not a fact', () {
      // A close-up that fills the frame with one corner looks like this.
      final closeUp = analyseBanknoteText('500');
      expect(closeUp.rupees, 500);
      expect(closeUp.evidence, BanknoteEvidence.weak);
    });

    test('a price tag is only a weak candidate', () {
      final price = analyseBanknoteText('TOTAL 500 RUPEES');
      expect(price.rupees, 500);
      expect(price.evidence, BanknoteEvidence.weak);

      final receipt = analyseBanknoteText('TOTAL 500\nVAT 25\nCARD 1234');
      expect(receipt.rupees, 500);
      expect(receipt.evidence, BanknoteEvidence.weak);
    });

    test('serial numbers are not denominations', () {
      expect(
        analyseBanknoteText('0AB 123456 7CD 987654').problem,
        BanknoteProblem.notABanknote,
      );
    });

    test('two different values in view are refused', () {
      final reading = analyseBanknoteText(
        'RESERVE BANK OF INDIA 500 500 100 100',
      );
      expect(reading.isNote, isFalse);
      expect(reading.problem, BanknoteProblem.mixedNotes);
    });

    test('a 2000 note is read whole, not as 200', () {
      final reading = analyseBanknoteText('RESERVE BANK OF INDIA 2000 2000');
      expect(reading.rupees, 2000);
      expect(reading.evidence, BanknoteEvidence.strong);
    });

    test('grouping commas do not hide a value', () {
      final reading = analyseBanknoteText('RESERVE BANK OF INDIA 2,000 2,000');
      expect(reading.rupees, 2000);
      expect(reading.evidence, BanknoteEvidence.strong);
    });

    test('several notes of the same value are one answer', () {
      expect(analyseBanknoteText('500 500 500 500').rupees, 500);
    });

    test('nothing readable is not a banknote', () {
      expect(analyseBanknoteText('').problem, BanknoteProblem.notABanknote);
      expect(
        analyseBanknoteText('hello there').problem,
        BanknoteProblem.notABanknote,
      );
    });

    test('a number attached to letters is ignored', () {
      // "Rs500" style product codes must not become a note value.
      expect(
        analyseBanknoteText('ITEM SKU500').problem,
        BanknoteProblem.notABanknote,
      );
    });
  });

  group('spokenRupeeAmount', () {
    test('English uses words', () {
      expect(spokenRupeeAmount(10, hindi: false), 'Ten rupees.');
      expect(spokenRupeeAmount(100, hindi: false), 'One hundred rupees.');
      expect(spokenRupeeAmount(500, hindi: false), 'Five hundred rupees.');
      expect(spokenRupeeAmount(2000, hindi: false), 'Two thousand rupees.');
    });

    test('Hindi speaks the digits, adding no new Hindi wording', () {
      expect(spokenRupeeAmount(500, hindi: true), '500');
    });
  });

  group('banknote sentences', () {
    const english = CueStrings(CueLanguage.english);
    const hindi = CueStrings(CueLanguage.hindi);

    test('a confident note is stated plainly', () {
      expect(english.banknoteAnswer(500), 'Five hundred rupees.');
    });

    test('an uncertain note is explicitly hedged', () {
      expect(
        english.banknoteUncertain(500),
        'I think it is five hundred rupees. I cannot see the whole note.',
      );
    });

    test('Hindi never asserts an uncertain value', () {
      expect(hindi.banknoteUncertain(500), hindi.somethingThere);
    });
  });
}
