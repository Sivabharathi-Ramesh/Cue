import 'detected_object.dart';

/// Requires an object to be seen more than once before Cue trusts it.
///
/// A single YOLO pass on a blank wall will occasionally invent a "person" or a
/// "tv". Speaking that is what makes the mode feel random to a blind user. An
/// object now has to survive [passesToConfirm] consecutive passes, and once
/// trusted it stays trusted for [passesToForget] misses so a nudge of the
/// camera does not make a real chair disappear mid-sentence.
class ObjectTracker {
  ObjectTracker({this.passesToConfirm = 2, this.passesToForget = 2});

  /// Consecutive passes an object must appear in before it is spoken.
  final int passesToConfirm;

  /// Consecutive passes an object may be missing before it is dropped.
  final int passesToForget;

  /// Consecutive hits per class name.
  final Map<String, int> _hits = <String, int>{};

  /// Consecutive misses per class name.
  final Map<String, int> _misses = <String, int>{};

  /// Latest known geometry per class name.
  final Map<String, DetectedObject> _latest = <String, DetectedObject>{};

  /// Feeds one detector pass in and returns the objects Cue may speak about.
  ///
  /// [trustImmediately] is for a manual double-tap: the user asked, so the
  /// first pass is the answer even if the live check would have waited.
  List<DetectedObject> update(
    List<DetectedObject> seen, {
    bool trustImmediately = false,
  }) {
    // Keep the best detection per class: two boxes of the same class are the
    // same thing seen twice, not two things.
    final best = <String, DetectedObject>{};
    for (final object in seen) {
      final previous = best[object.name];
      if (previous == null || object.confidence > previous.confidence) {
        best[object.name] = object;
      }
    }

    for (final entry in best.entries) {
      _hits[entry.key] = (_hits[entry.key] ?? 0) + 1;
      _misses.remove(entry.key);
      _latest[entry.key] = entry.value;
    }

    for (final name in _hits.keys.toList()) {
      if (best.containsKey(name)) continue;
      final misses = (_misses[name] ?? 0) + 1;
      _misses[name] = misses;
      if (misses >= passesToForget) {
        _hits.remove(name);
        _misses.remove(name);
        _latest.remove(name);
      }
    }

    final confirmed = <DetectedObject>[];
    for (final entry in _hits.entries) {
      final needed = trustImmediately ? 1 : passesToConfirm;
      if (entry.value < needed) continue;
      final object = _latest[entry.key];
      if (object != null) confirmed.add(object);
    }

    // Nearest first: for walking, distance matters more than label order.
    confirmed.sort((a, b) {
      final distanceA = a.distanceMeters ?? 99;
      final distanceB = b.distanceMeters ?? 99;
      final byDistance = distanceA.compareTo(distanceB);
      if (byDistance != 0) return byDistance;
      return b.confidence.compareTo(a.confidence);
    });

    return confirmed;
  }

  /// Forgets everything. Used when the camera stops or the mode changes.
  void reset() {
    _hits.clear();
    _misses.clear();
    _latest.clear();
  }
}
