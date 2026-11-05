/// Splits a page of recognised text into the sentence-sized pieces Cue reads
/// one at a time.
///
/// A reader that dumps a whole page in one utterance cannot be steered. Once
/// the text is a list of sentences, the user can say "next", "back", "repeat"
/// or "start over" and hear exactly one piece each time.
///
/// The rules are deliberately simple and script-aware:
///
/// - `.`, `!`, `?` and `;` end a sentence when followed by whitespace;
/// - the Devanagari danda `।` and double danda `॥` end a sentence even when no
///   space follows;
/// - common abbreviations ("Dr.", "No.", initials) do not end a sentence;
/// - a very long sentence is cut at a comma or space, because a 400-character
///   utterance is impossible to navigate even if it is one grammatical
///   sentence.
library;

/// The longest piece the reader will hand to the voice in one go.
///
/// Long enough to keep a natural sentence together, short enough that "next"
/// moves at a useful pace and the user is never trapped inside a paragraph.
const int defaultMaxSentenceLength = 220;

/// Splits [text] into speakable sentences.
///
/// The returned pieces keep their original punctuation, so the voice engine
/// still hears where a sentence ended. Empty text returns an empty list.
List<String> splitSentences(
  String text, {
  int maxLength = defaultMaxSentenceLength,
}) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.isEmpty) return const <String>[];

  // Latin punctuation needs following whitespace so "3.5" and "e.g." are not
  // torn apart. Danda needs no whitespace in Hindi typography.
  final boundary = RegExp(r'(?<=[.!?;])\s+|(?<=[।॥])\s*');
  final pieces = <String>[];
  for (final part in clean.split(boundary)) {
    final trimmed = part.replaceFirst(RegExp(r'^[।॥\s]+'), '').trim();
    if (trimmed.isEmpty) continue;
    if (!RegExp(r'[\p{L}\p{M}\p{N}]', unicode: true).hasMatch(trimmed)) {
      // Punctuation-only fragments carry nothing to read.
      continue;
    }
    pieces.add(trimmed);
  }

  final sentences = <String>[];
  for (final piece in _mergeAbbreviations(pieces)) {
    sentences.addAll(_chunk(piece, maxLength));
  }
  return sentences;
}

/// Abbreviations that end with a full stop but do not end a sentence.
const Set<String> _abbreviations = <String>{
  'mr',
  'mrs',
  'ms',
  'dr',
  'prof',
  'sr',
  'jr',
  'st',
  'vs',
  'etc',
  'no',
  'fig',
  'approx',
  'e.g',
  'i.e',
};

/// Joins a piece back onto the next one when it ends in an abbreviation.
List<String> _mergeAbbreviations(List<String> pieces) {
  final out = <String>[];
  var buffer = '';
  for (final piece in pieces) {
    buffer = buffer.isEmpty ? piece : '$buffer $piece';
    if (_endsWithAbbreviation(buffer)) continue;
    out.add(buffer);
    buffer = '';
  }
  if (buffer.isNotEmpty) out.add(buffer);
  return out;
}

bool _endsWithAbbreviation(String text) {
  final match = RegExp(r'([A-Za-z]{1,4})\.$').firstMatch(text);
  if (match == null) return false;
  final word = match.group(1)!;
  // A single capital is an initial, as in "J. K. Rowling".
  if (word.length == 1) return true;
  return _abbreviations.contains(word.toLowerCase());
}

/// Cuts an over-long sentence at punctuation or whitespace.
Iterable<String> _chunk(String sentence, int maxLength) sync* {
  final limit = maxLength < 40 ? 40 : maxLength;
  var rest = sentence;

  while (rest.length > limit) {
    var cut = -1;

    // Prefer a natural break inside the second half of the window.
    for (var i = limit; i >= limit ~/ 2; i--) {
      final char = rest[i - 1];
      if (char == ',' ||
          char == ';' ||
          char == ':' ||
          char == '\u2014' ||
          char == '\u2013') {
        cut = i;
        break;
      }
    }

    if (cut < 0) {
      final space = rest.lastIndexOf(' ', limit);
      cut = space > 0 ? space : _safeCut(rest, limit);
    }

    final piece = rest.substring(0, cut).trim();
    if (piece.isNotEmpty) yield piece;
    rest = rest.substring(cut).trim();
  }

  if (rest.isNotEmpty) yield rest;
}

/// A last-resort cut that avoids splitting a letter from its combining mark.
int _safeCut(String text, int limit) {
  var cut = limit.clamp(1, text.length);
  final mark = RegExp(r'\p{M}', unicode: true);
  while (cut > 1 && cut < text.length && mark.hasMatch(text[cut])) {
    cut--;
  }
  return cut;
}
