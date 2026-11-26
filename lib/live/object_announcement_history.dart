import '../vision/detected_object.dart';

/// Remembers spoken objects through a short interruption in detection.
class ObjectAnnouncementHistory {
  static const _returnWindow = Duration(seconds: 6);
  final _recent =
      <({DetectedObject object, DateTime seenAt, Object? identity})>[];

  /// Associates each visible object with at most one previous announcement.
  /// Keep the last box and time current while the speaker is busy as well.
  Set<DetectedObject> observe(
    Iterable<DetectedObject> visible,
    DateTime now, {
    Object? Function(DetectedObject)? identityOf,
  }) {
    _recent.removeWhere(
      (entry) => now.difference(entry.seenAt) >= _returnWindow,
    );
    final used = <int>{};
    final alreadySpoken = <DetectedObject>{};
    for (final object in visible) {
      final identity = identityOf?.call(object);
      int? best;
      var bestOverlap = 0.45;
      for (var i = 0; i < _recent.length; i++) {
        if (used.contains(i)) continue;
        final previous = _recent[i].object;
        if (previous.label != object.label ||
            previous.direction != object.direction) {
          continue;
        }
        if (identity != null && identical(identity, _recent[i].identity)) {
          best = i;
          break;
        }
        final overlap = boxIou(previous.box, object.box);
        if (overlap > bestOverlap) {
          best = i;
          bestOverlap = overlap;
        }
      }
      if (best == null) continue;
      used.add(best);
      alreadySpoken.add(object);
      _recent[best] = (
        object: object,
        seenAt: now,
        identity: identity ?? _recent[best].identity,
      );
    }
    return alreadySpoken;
  }

  /// Only record objects that made it into an actual description.
  void remember(
    Iterable<DetectedObject> spoken,
    DateTime now, {
    Object? Function(DetectedObject)? identityOf,
  }) {
    for (final object in spoken) {
      if (_recent.any((entry) => identical(entry.object, object))) continue;
      _recent.add((
        object: object,
        seenAt: now,
        identity: identityOf?.call(object),
      ));
    }
  }

  void reset() => _recent.clear();
}
