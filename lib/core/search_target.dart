/// Everyday items supported by the detector's vocabulary.
enum SearchTarget {
  keys('Keys', 'चाबी', {'keys'}, needsDetail: true),
  phone('Phone', 'फ़ोन', {'mobile phone', 'cell phone'}),
  glasses('Glasses', 'चश्मा', {'glasses'}, needsDetail: true),
  pen('Pen', 'पेन', {'pen'}, needsDetail: true),
  bottle('Bottle', 'बोतल', {'bottle', 'water bottle'}),
  wallet('Wallet', 'बटुआ', {'wallet'}, needsDetail: true),
  remote(
    'Remote control',
    'रिमोट',
    {'remote control'},
    aliases: {'remote', 'tv remote'},
    needsDetail: true,
  ),
  charger(
    'Charger',
    'चार्जर',
    {'charger'},
    aliases: {'phone charger', 'wall charger'},
    needsDetail: true,
  ),
  comb('Comb', 'कंघी', {'comb'}, needsDetail: true),
  mug('Mug', 'मग', {'mug'});

  static const quickChoices = [keys, phone, glasses, pen, bottle];

  const SearchTarget(
    this.english,
    this.hindi,
    this.labels, {
    this.aliases = const {},
    this.needsDetail = false,
  });
  final String english;
  final String hindi;
  final Set<String> labels;
  final Set<String> aliases;

  /// Small items benefit from scanning closer views of the camera frame.
  final bool needsDetail;
}
