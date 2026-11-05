/// Text comparison helpers shared by the audio bus and the live pipeline.
///
/// Kept deliberately free of Flutter and ML Kit imports so it can be unit
/// tested without a device. OCR output is noisy: the same page can come back
/// with different punctuation, casing or a missing word on every frame. These
/// helpers answer two questions the live pipeline needs:
///
///   1. Is this frame the same page as the last one?  -> [tokenJaccard]
///   2. Is there enough new text to be worth speaking? -> [newTokenRatio]
library;

/// Lowercases, strips punctuation and collapses whitespace.
///
/// The result is only used for comparison. What is spoken is always the
/// cleaned original text, never this normalised form.
///
/// Unicode-aware: Devanagari letters, vowel signs and nukta marks are kept, so
/// two Hindi frames of the same page compare as similar instead of both
/// normalising to an empty string.
String normalizeText(String raw) {
  final lower = raw.toLowerCase();
  final letters = lower.replaceAll(
    RegExp(r'[^\p{L}\p{M}\p{N}\u200C\u200D ]+', unicode: true),
    ' ',
  );
  return letters.replaceAll(RegExp(r'\s+'), ' ').trim();
}

Set<String> _tokens(String text) {
  final normalised = normalizeText(text);
  if (normalised.isEmpty) return const <String>{};
  return normalised.split(' ').where((word) => word.isNotEmpty).toSet();
}

/// Jaccard similarity of the word sets: intersection / union, from 0 to 1.
///
/// Two frames of the same page usually score above 0.9 even when OCR drops a
/// word. Two different pages score close to 0.
double tokenJaccard(String a, String b) {
  final left = _tokens(a);
  final right = _tokens(b);
  if (left.isEmpty && right.isEmpty) return 0;

  var intersection = 0;
  for (final word in left) {
    if (right.contains(word)) intersection++;
  }
  final union = left.length + right.length - intersection;
  if (union == 0) return 0;
  return intersection / union;
}

/// Fraction of [current] words that did not appear in [previous].
///
/// A value near 0 means "the same page again" and should not be re-spoken.
/// A value above roughly 0.35 means enough new material arrived that the user
/// is looking at something new.
double newTokenRatio(String previous, String current) {
  final currentTokens = _tokens(current);
  if (currentTokens.isEmpty) return 0;
  if (previous.trim().isEmpty) return 1;

  final previousTokens = _tokens(previous);
  var fresh = 0;
  for (final word in currentTokens) {
    if (!previousTokens.contains(word)) fresh++;
  }
  return fresh / currentTokens.length;
}

/// Character-bigram similarity (Sørensen-Dice), from 0 to 1.
///
/// Used for frame-to-frame stability rather than for "is this new?". Word
/// sets are too brittle on a short line: OCR reading "nine" as "9" changes a
/// fifth of the tokens on a five-word sign. Character bigrams survive that
/// while still scoring two genuinely different pages far apart.
double charBigramSimilarity(String a, String b) {
  final left = normalizeText(a).replaceAll(' ', '');
  final right = normalizeText(b).replaceAll(' ', '');
  if (left.isEmpty || right.isEmpty) {
    return left == right ? 1 : 0;
  }
  if (left.length < 2 || right.length < 2) {
    return left == right ? 1 : 0;
  }

  final counts = <String, int>{};
  for (var i = 0; i < left.length - 1; i++) {
    final bigram = left.substring(i, i + 2);
    counts[bigram] = (counts[bigram] ?? 0) + 1;
  }

  var intersection = 0;
  for (var i = 0; i < right.length - 1; i++) {
    final bigram = right.substring(i, i + 2);
    final remaining = counts[bigram] ?? 0;
    if (remaining > 0) {
      intersection++;
      counts[bigram] = remaining - 1;
    }
  }

  return (2 * intersection) / ((left.length - 1) + (right.length - 1));
}
