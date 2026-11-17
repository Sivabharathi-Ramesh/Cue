import 'dart:ui';

import 'detected_object.dart';

/// Requires an object to be seen more than once before Cue trusts it.
///
/// A single YOLO pass on a blank wall will occasionally invent a "person" or a
/// "tv". Speaking that is what makes the mode feel random to a blind user. An
/// object now has to survive [passesToConfirm] consecutive passes, and once
/// trusted it stays trusted for [passesToForget] misses so a nudge of the
/// camera does not make a real chair disappear mid-sentence.
///
/// Objects are tracked as *instances*, not by class name. Two chairs are two
/// things a user can walk into, so collapsing them into one "chair" is not an
/// acceptable shortcut. Each instance is matched to the previous pass by
/// position and size; a new chair seen beside an old one gets its own track.
///
/// Boxes are smoothed when a track is matched. The detector's box jitters by a
/// few percent from frame to frame, which is enough to flip a spoken distance
/// between "about a metre" and "about two metres" and make the same scene
/// sound new. Smoothing damps that without hiding genuine movement.
class ObjectTracker {
  ObjectTracker({
    this.passesToConfirm = 2,
    this.passesToForget = 2,
    this.smoothing = 0.55,
  });

  /// Consecutive passes an object must appear in before it is spoken.
  final int passesToConfirm;

  /// Consecutive passes an object may be missing before it is dropped.
  final int passesToForget;

  /// How much of a matched box comes from the newest pass, 0-1.
  ///
  /// 1.0 would be no smoothing at all. The default keeps the box responsive
  /// enough to follow a hand while removing most of the frame-to-frame noise.
  final double smoothing;

  /// Live instances, keyed by track id.
  final Map<int, _Track> _tracks = <int, _Track>{};

  int _nextId = 1;

  /// Feeds one detector pass in and returns the objects Cue may speak about.
  ///
  /// [trustImmediately] is for a manual double-tap: the user asked, so the
  /// first pass is the answer even if the live check would have waited.
  List<DetectedObject> update(
    List<DetectedObject> seen, {
    bool trustImmediately = false,
  }) {
    final detections = _mergeDuplicates(seen);
    final observed = <int>{};

    // Match the strongest detections first, so a confident box claims its
    // track before a weaker neighbouring box can.
    for (final detection in detections) {
      _Track? best;
      var bestScore = 0.0;

      for (final track in _tracks.values) {
        if (observed.contains(track.id)) continue;
        if (track.object.name != detection.name) continue;

        final score = _matchScore(track.object, detection);
        if (score > bestScore) {
          best = track;
          bestScore = score;
        }
      }

      if (best != null) {
        observed.add(best.id);
        best.observe(detection, smoothing);
      } else {
        final track = _Track(id: _nextId++, object: detection);
        _tracks[track.id] = track;
        observed.add(track.id);
      }
    }

    for (final track in _tracks.values.toList(growable: false)) {
      if (observed.contains(track.id)) continue;
      track.misses++;
      if (track.misses >= passesToForget) _tracks.remove(track.id);
    }

    final confirmed = <DetectedObject>[];
    for (final track in _tracks.values) {
      final needed = trustImmediately ? 1 : passesToConfirm;
      // A manual answer is about the frame the user just asked about, so an
      // object that survived only because it is being bridged through a miss
      // is not part of the answer. Including it would let a stale position
      // sit beside the object's real one and produce "two chairs" for one.
      if (trustImmediately && !observed.contains(track.id)) continue;
      if (track.hits < needed) continue;
      confirmed.add(track.object);
    }

    // Nearest first: for walking, distance matters more than label order.
    confirmed.sort(_byImportance);
    return confirmed;
  }

  /// Forgets everything. Used when the camera stops or the mode changes.
  void reset() {
    _tracks.clear();
    _nextId = 1;
  }

  /// Two classes on one box are one thing, not two. Keep the confident label.
  List<DetectedObject> _mergeDuplicates(List<DetectedObject> seen) {
    final sorted = [...seen]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <DetectedObject>[];
    for (final object in sorted) {
      final duplicate = kept.any((other) => _iou(other.box, object.box) >= 0.6);
      if (!duplicate) kept.add(object);
    }
    return kept;
  }

  /// How plausible it is that [detection] is the same physical object as
  /// [track]. Zero means "not the same thing".
  double _matchScore(DetectedObject track, DetectedObject detection) {
    // An object cannot change size this much between two frames. A sudden
    // change means a different object now occupies the box.
    final areaRatio = detection.area / track.area;
    if (areaRatio < 0.35 || areaRatio > 2.85) return 0;

    final iou = _iou(track.box, detection.box);
    final centreDistance = (track.box.center - detection.box.center).distance;

    // Overlap is the strongest evidence. For small objects, or a fast hand,
    // a close centre with little overlap still counts; anything farther away
    // is a different instance.
    if (iou < 0.2 && centreDistance > 0.12) return 0;

    final proximity = (1 - centreDistance / 0.2).clamp(0.0, 1.0);
    final score = iou * 2.0 + proximity;
    return score >= 0.5 ? score : 0;
  }

  double _iou(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.width <= 0 || intersection.height <= 0) return 0;
    final intersectionArea = intersection.width * intersection.height;
    final union = a.width * a.height + b.width * b.height - intersectionArea;
    return union <= 0 ? 0 : intersectionArea / union;
  }

  static int _byImportance(DetectedObject a, DetectedObject b) {
    final distanceA = a.distanceMeters ?? double.infinity;
    final distanceB = b.distanceMeters ?? double.infinity;
    final byDistance = distanceA.compareTo(distanceB);
    if (byDistance != 0) return byDistance;

    // Without a trustworthy distance, the bigger box is the better answer:
    // it is the thing closest to the camera, not a speck in the corner.
    final byArea = b.area.compareTo(a.area);
    if (byArea != 0) return byArea;
    return b.confidence.compareTo(a.confidence);
  }
}

class _Track {
  _Track({required this.id, required this.object});

  final int id;
  DetectedObject object;
  int hits = 1;
  int misses = 0;

  void observe(DetectedObject next, double alpha) {
    final previous = object.box;
    final box = Rect.fromLTRB(
      _lerp(previous.left, next.box.left, alpha),
      _lerp(previous.top, next.box.top, alpha),
      _lerp(previous.right, next.box.right, alpha),
      _lerp(previous.bottom, next.box.bottom, alpha),
    );

    object = DetectedObject(
      name: next.name,
      confidence: _lerp(object.confidence, next.confidence, alpha),
      box: box,
      // Colour is sampled per frame. Keeping the last known reading avoids
      // losing the colour entirely when one frame is too small to sample.
      colour: next.colour ?? object.colour,
    );
    hits++;
    misses = 0;
  }
}

double _lerp(double from, double to, double alpha) =>
    from + (to - from) * alpha;
