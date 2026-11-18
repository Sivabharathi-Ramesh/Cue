/// Offline recognition of Indian rupee banknotes.
///
/// This is deliberately not a trained classifier yet. A currency classifier
/// needs a labelled dataset Cue does not have, and an unearned guess about
/// money is worse than no answer: handing over a ₹2000 note as a ₹200 is a
/// real loss. Version 1 therefore reads the large printed denomination with
/// the on-device text recogniser and refuses unless the evidence agrees.
///
/// Indian notes make that possible. The value is printed in large numerals in
/// more than one place, every note carries "RESERVE BANK OF INDIA" in Latin
/// script, and the serial number is a six-digit alphanumeric string rather
/// than a denomination. A repeated numeral plus the banner is strong evidence;
/// one lonely numeral on a receipt or a price tag is not.
library;

/// Values of the rupee notes in current circulation.
///
/// ₹1000 is absent on purpose: the series was withdrawn in 2016 and a note
/// bearing that value is either obsolete or not a rupee note.
const Set<int> rupeeDenominations = <int>{10, 20, 50, 100, 200, 500, 2000};

/// How much agreement the frame contained, weakest first.
enum BanknoteEvidence {
  /// Nothing worth speaking.
  none,

  /// One denomination numeral, with no banner and no repetition. A close-up
  /// that fills the frame with a single corner looks like this, and so does a
  /// price tag. It is a candidate, never a fact.
  weak,

  /// The same value appears more than once, but the banner was not read. A
  /// folded note can hide the top banner, so this is useful, but it needs a
  /// second frame before Cue speaks.
  medium,

  /// A repeated value corroborated by the RBI banner or the word RUPEES.
  strong,
}

/// Why a frame did not produce a denomination.
enum BanknoteProblem {
  none,

  /// No denomination numeral at all.
  notABanknote,

  /// Two different values are readable, for example two notes fanned out.
  mixedNotes,

  /// A manual check timed out without a usable numeral. The analyser itself
  /// returns [notABanknote] for an empty frame; this value lets the pipeline
  /// ask for a better view instead of claiming the object is not money.
  unclear,
}

/// What one frame said about the note in view.
class BanknoteReading {
  const BanknoteReading({
    this.rupees,
    this.evidence = BanknoteEvidence.none,
    this.problem = BanknoteProblem.none,
  });

  /// The denomination, or null when Cue refuses to commit.
  final int? rupees;

  final BanknoteEvidence evidence;
  final BanknoteProblem problem;

  bool get isNote => rupees != null;

  /// True when the value is corroborated in the same frame.
  bool get isStrong => rupees != null && evidence == BanknoteEvidence.strong;

  @override
  String toString() =>
      'BanknoteReading(rupees=$rupees, evidence=${evidence.name}, '
      'problem=${problem.name})';
}

/// Reads a note from the text one camera frame produced.
///
/// [rawText] is whatever the Latin-script recogniser returned. This function
/// does no I/O, so the evidence rules can be tested without a camera or a
/// real note.
BanknoteReading analyseBanknoteText(String rawText) {
  final text = _removeGroupingCommas(rawText).toUpperCase();
  final counts = _denominationCounts(text);

  if (counts.isEmpty) {
    return const BanknoteReading(problem: BanknoteProblem.notABanknote);
  }

  final repeated = <MapEntry<int, int>>[
    for (final entry in counts.entries)
      if (entry.value >= 2) entry,
  ]..sort((a, b) => b.value.compareTo(a.value));

  // A note prints one value, repeatedly. Two values repeated in the same frame
  // means two notes (or one badly read note), and either way the honest answer
  // is that Cue cannot choose.
  if (repeated.length >= 2) {
    return const BanknoteReading(problem: BanknoteProblem.mixedNotes);
  }

  if (repeated.length == 1) {
    final value = repeated.single.key;
    final corroborated = _hasBanknoteBanner(text) || _hasRupeeWord(text);
    return BanknoteReading(
      rupees: value,
      evidence: corroborated
          ? BanknoteEvidence.strong
          : BanknoteEvidence.medium,
    );
  }

  // Only single occurrences were found. Two different values are still a
  // fan of notes; one value with the RBI banner is a plausible close-up, and
  // one value without it is a candidate that needs another frame.
  if (counts.length >= 2) {
    return const BanknoteReading(problem: BanknoteProblem.mixedNotes);
  }

  final value = counts.keys.single;
  if (_hasBanknoteBanner(text)) {
    return BanknoteReading(rupees: value, evidence: BanknoteEvidence.medium);
  }

  return BanknoteReading(rupees: value, evidence: BanknoteEvidence.weak);
}

/// Phrases printed on every current Indian note in Latin script.
///
/// The banner is the strongest currency signal OCR can see. "RUPEES" alone is
/// not enough: price tags and receipts in India use it too.
const List<String> _banknoteBanners = <String>[
  'RESERVE BANK OF INDIA',
  'MAHATMA GANDHI',
  'I PROMISE TO PAY',
  'GUARANTEED BY THE CENTRAL GOVERNMENT',
];

bool _hasBanknoteBanner(String text) {
  final compact = text.replaceAll(RegExp(r'\s+'), ' ');
  return _banknoteBanners.any(compact.contains);
}

bool _hasRupeeWord(String text) => RegExp(r'\bRUPEES?\b').hasMatch(text);

/// Counts standalone denomination numerals in [text].
///
/// Boundary rules matter more than the regex. A serial number, a phone number
/// and a price all contain digit runs; only an exact note value, standing on
/// its own and at most four digits long, is allowed to count.
Map<int, int> _denominationCounts(String text) {
  final counts = <int, int>{};

  for (final match in RegExp(r'[0-9]+').allMatches(text)) {
    final run = match.group(0)!;
    if (run.length < 2 || run.length > 4) continue;
    if (run.startsWith('0')) continue;
    if (_isLatinLetter(text, match.start - 1) ||
        _isLatinLetter(text, match.end)) {
      continue;
    }

    // "0.500" is a decimal, not a denomination.
    if (match.start >= 2 &&
        text[match.start - 1] == '.' &&
        _isDigit(text.codeUnitAt(match.start - 2))) {
      continue;
    }

    final value = int.parse(run);
    if (!rupeeDenominations.contains(value)) continue;
    counts.update(value, (count) => count + 1, ifAbsent: () => 1);
  }

  return counts;
}

/// Removes the comma from "2,000" so the value survives as one run.
String _removeGroupingCommas(String text) {
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == ',' &&
        i > 0 &&
        i + 1 < text.length &&
        _isDigit(text.codeUnitAt(i - 1)) &&
        _isDigit(text.codeUnitAt(i + 1))) {
      continue;
    }
    buffer.write(char);
  }
  return buffer.toString();
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

bool _isLatinLetter(String text, int index) {
  if (index < 0 || index >= text.length) return false;
  final code = text.codeUnitAt(index);
  return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
}
