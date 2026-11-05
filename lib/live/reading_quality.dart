/// Decides whether OCR output is worth speaking.
///
/// ML Kit's Latin recogniser is trained on **printed** text. Point it at
/// handwriting and it still returns a string, but the string is often
/// confident-looking nonsense. Speaking that is worse than saying nothing:
/// a blind user has no way to tell a wrong reading from a right one.
///
/// This file is the honesty gate. It combines the recogniser's own confidence
/// with a structural check that catches the shapes gibberish tends to take:
/// symbol soup, one- and two-character fragments, endless repetitions.
///
/// It is deliberately conservative about rejecting: a page of numbers, an
/// acronym, or a single short sign must still be read. It refuses only what
/// looks like marks rather than words.
library;

/// Minimum mean line confidence for a reading to be trusted outright.
///
/// Calibration on the test camera (2026-11-03, 1280x720):
///
/// - clear printed page: 0.82–0.85, read correctly;
/// - cursive/handwritten page: 0.68, read with missing words and letters.
///
/// 0.75 sits between the two. A dim or blurred photo of real print can dip
/// below it, and when it does the app still gives the user something, but
/// only as an explicitly flagged doubt rather than as a confident answer.
const double minTrustedConfidence = 0.75;

/// Minimum mean line confidence for any reading to be spoken, even doubtfully.
///
/// Below this, the model is not producing words in any consistent sense:
/// the page could be anything, and a blind user cannot tell. 0.50 is a
/// starting point to be recalibrated on real handwriting; it follows the
/// calibration gap between a 0.68 cursive page that was mostly correct and
/// the noise seen by the recogniser on harder samples.
const double minUncertainConfidence = 0.5;

/// Characters that ordinary printed text can contain without being noise.
///
/// Typographic quotes, dashes and bullets are included because a real page
/// uses them, and a page full of them is still text.
const String _punctuation =
    ".,;:!?%\$£€₹/-()[]'"
    '\u2018\u2019\u201c\u201d\u2013\u2014\u2026\u2022"&+#'
    '\u0964\u0965\u200C\u200D';

/// How much the recogniser and the shape check believe a reading.
enum ReadingTier {
  /// Word-shaped, with confidence at least [minTrustedConfidence].
  certain,

  /// Word-shaped but only [minUncertainConfidence]–[minTrustedConfidence],
  /// or the platform cannot report confidence.
  ///
  /// Can be spoken, but only after saying clearly that the app is unsure.
  uncertain,

  /// The text is absent or is not word-shaped, or confidence is too low to
  /// risk even a doubtful sentence. Do not speak it.
  refused,
}

class ReadingQuality {
  const ReadingQuality({
    required this.confidence,
    required this.plausible,
    required this.tier,
    this.reason,
  });

  /// Mean confidence of the recognised lines, 0–1, or null when the platform
  /// does not report one (iOS).
  final double? confidence;

  /// Whether the text has the shape of language rather than noise.
  final bool plausible;

  /// Whether a blind user may hear the result at all.
  final ReadingTier tier;

  /// Why the text was rejected or only doubtfully trusted, for the debug log.
  /// Null for a [ReadingTier.certain] result.
  final String? reason;

  /// True when the reading can be spoken, with or without a doubt flag.
  bool get speakable => tier != ReadingTier.refused;

  factory ReadingQuality.of(String text, double? confidence) {
    if (text.trim().length < 2) {
      return ReadingQuality(
        confidence: confidence,
        plausible: false,
        tier: ReadingTier.refused,
        reason: 'too short',
      );
    }
    if (!looksLikeText(text)) {
      return ReadingQuality(
        confidence: confidence,
        plausible: false,
        tier: ReadingTier.refused,
        reason: 'not word-shaped',
      );
    }

    // Missing confidence cannot support an unqualified answer.
    if (confidence == null) {
      return const ReadingQuality(
        confidence: null,
        plausible: true,
        tier: ReadingTier.uncertain,
        reason: 'no confidence reported',
      );
    }

    if (confidence >= minTrustedConfidence) {
      return ReadingQuality(
        confidence: confidence,
        plausible: true,
        tier: ReadingTier.certain,
      );
    }
    if (confidence >= minUncertainConfidence) {
      return ReadingQuality(
        confidence: confidence,
        plausible: true,
        tier: ReadingTier.uncertain,
        reason: 'low confidence',
      );
    }

    return ReadingQuality(
      confidence: confidence,
      plausible: true,
      tier: ReadingTier.refused,
      reason: 'confidence too low',
    );
  }

  @override
  String toString() {
    final confidence = this.confidence?.toStringAsFixed(2) ?? 'n/a';
    final reason = this.reason == null ? '' : ', ${this.reason}';
    return 'confidence $confidence, tier ${tier.name}$reason';
  }
}

/// True when [text] looks like words rather than OCR noise.
///
/// Rules, all cheap and script-aware:
///
/// - at least 85 % of visible characters are letters, digits, combining marks
///   or ordinary punctuation (symbol soup fails);
/// - at least 60 % of tokens look like words or numbers;
/// - a page of mostly one- and two-character fragments fails, which is what
///   handwriting usually fragments into;
/// - a single enormous unbroken token fails.
///
/// Devanagari vowel signs are combining marks (`\p{M}`), not letters, so a
/// Latin-only test would reject perfectly good Hindi. The classes here are
/// Unicode-aware on purpose.
bool looksLikeText(String text) {
  final trimmed = text.trim();
  if (trimmed.length < 2) return false;

  final meaningfulChar = RegExp(r'[\p{L}\p{M}\p{N}]', unicode: true);
  var visible = 0;
  var meaningful = 0;
  for (final rune in trimmed.runes) {
    final char = String.fromCharCode(rune);
    if (char.trim().isEmpty) continue;
    visible++;
    if (meaningfulChar.hasMatch(char)) {
      meaningful++;
    } else if (_punctuation.contains(char)) {
      meaningful++;
    }
  }
  if (visible == 0) return false;
  if (meaningful / visible < 0.85) return false;

  final tokens = trimmed
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
  if (tokens.isEmpty) return false;

  var wordlike = 0;
  for (final token in tokens) {
    if (_wordlike(token)) wordlike++;
  }
  if (wordlike / tokens.length < 0.6) return false;

  if (tokens.length >= 4) {
    final fragments = tokens.where((token) => token.length <= 2).length;
    if (fragments / tokens.length > 0.7) return false;
  }

  if (tokens.length == 1 && tokens.first.length > 24) return false;

  return true;
}

bool _wordlike(String raw) {
  final token = raw.replaceAll(
    RegExp(r'^[^\p{L}\p{M}\p{N}]+|[^\p{L}\p{M}\p{N}]+$', unicode: true),
    '',
  );
  if (token.isEmpty || token.length > 30) return false;

  // "aaaaaaa" or "111111" is a recognition loop, not a word.
  if (token.length >= 4 && token.split('').toSet().length == 1) return false;

  final hasLetter = RegExp(r'\p{L}', unicode: true).hasMatch(token);
  final hasDigit = RegExp(r'\p{N}', unicode: true).hasMatch(token);
  if (!hasLetter && !hasDigit) return false;

  // One- and two-character tokens carry too little signal to judge on their
  // own: "Dr", "TV", "52", "I" and "है" are all real. Fragment soup is caught
  // by the density rule above instead.
  if (token.length <= 2) return true;

  // A run of Latin consonants with no vowel, no digit and no capitals is the
  // shape most handwriting noise takes ("rnln", "fflrt"). Devanagari writes
  // its vowels as marks, so this rule only applies to Latin letters.
  final hasLatin = RegExp(r'[A-Za-z]').hasMatch(token);
  if (hasLatin &&
      hasLetter &&
      !hasDigit &&
      !RegExp(r'[aeiouyAEIOUY]').hasMatch(token)) {
    return token.length <= 4 && token == token.toUpperCase();
  }

  return true;
}
