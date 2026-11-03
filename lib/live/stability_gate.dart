import '../core/text_similarity.dart';

/// Requires the same text to appear in two consecutive analysed frames before
/// it is allowed to be spoken.
///
/// This is the first half of the "honest uncertainty" rule: one bad OCR frame
/// (motion blur, a hand crossing the page) must not become a confident
/// sentence. A second frame with the same words confirms it.
///
/// The gate only decides *stability*. Deciding whether the text is new enough
/// to re-speak belongs to the audio bus, which sees every result.
class StabilityGate {
  StabilityGate({this.similarityThreshold = 0.75});

  /// Two frames count as the same text at or above this character similarity.
  final double similarityThreshold;

  String _candidate = '';
  int _hits = 0;

  /// True once the current candidate has been seen in at least two frames.
  bool get isStable => _hits >= 2;

  /// The text currently being confirmed. Empty before any text is seen.
  String get candidate => _candidate;

  /// Feeds one OCR result in and returns true when it is stable.
  ///
  /// A materially different result resets the count, so a new page always
  /// needs its own second frame.
  bool add(String text) {
    final normalised = normalizeText(text);

    // A single letter is not a reading. Two characters happen on real signs
    // ("A1", "42"), so the floor is deliberately low.
    if (normalised.length < 2) {
      reset();
      return false;
    }

    if (_candidate.isNotEmpty &&
        charBigramSimilarity(normalised, _candidate) >= similarityThreshold) {
      _hits += 1;
    } else {
      _candidate = normalised;
      _hits = 1;
    }

    return isStable;
  }

  void reset() {
    _candidate = '';
    _hits = 0;
  }
}
