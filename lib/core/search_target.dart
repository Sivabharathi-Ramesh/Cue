/// Everyday items supported by the detector's vocabulary.
enum SearchTarget {
  keys('Keys', 'चाबी', {'keys'}),
  phone('Phone', 'फ़ोन', {'mobile phone', 'cell phone'}),
  glasses('Glasses', 'चश्मा', {'glasses'}),
  pen('Pen', 'पेन', {'pen'}),
  bottle('Bottle', 'बोतल', {'bottle', 'water bottle'});

  const SearchTarget(this.english, this.hindi, this.labels);
  final String english;
  final String hindi;
  final Set<String> labels;
}
