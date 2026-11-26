import 'dart:ui';

import 'detected_object.dart';
import 'object_colour.dart';

enum ObjectScanType { scene, item, itemWithText }

/// Looks for a match across two fresh frames, with time for missed detections.
class ManualObjectScan {
  ManualObjectScan({this.type = ObjectScanType.scene})
    : _region = type == ObjectScanType.scene ? null : _tighterCloseUp;

  static const _maxPasses = 5;
  static const _frameGap = Duration(milliseconds: 300);
  static const _closeUp = Rect.fromLTRB(0.14, 0.16, 0.86, 0.84);
  static const _tighterCloseUp = Rect.fromLTRB(0.25, 0.28, 0.75, 0.72);
  static const _fullFrame = Rect.fromLTRB(0, 0, 1, 1);

  final ObjectScanType type;

  /// Whether to begin near the middle of the view and describe one item.
  bool get focused => type != ObjectScanType.scene;

  final _tracker = ObjectTracker(passesToConfirm: 2);
  DateTime? _lastFrameAt;
  int _passes = 0;
  bool _sawFullFrameCandidate = false;
  Rect? _region;

  /// A close-up can find small items and check borderline full-frame labels.
  Rect? get region => _region;

  /// Keep background writing out of a text-only answer after widening.
  Rect get fallbackTextRegion =>
      _region == _tighterCloseUp ? _tighterCloseUp : _closeUp;

  bool ready(DateTime now) {
    final last = _lastFrameAt;
    return _passes < _maxPasses &&
        (last == null || now.difference(last) >= _frameGap);
  }

  /// Null means wait for another frame. An empty list is a final miss.
  List<DetectedObject>? observe(
    DateTime capturedAt,
    List<DetectedObject> seen,
  ) {
    if (!ready(capturedAt)) return null;
    final crop = region;
    _lastFrameAt = capturedAt;
    _passes++;
    if (crop == null && seen.isNotEmpty) _sawFullFrameCandidate = true;
    final detections = crop == null
        ? seen
        : [
            for (final object in seen)
              if (boxInFullFrame(object.box, crop) case final box?)
                DetectedObject(
                  name: object.name,
                  confidence: object.confidence,
                  box: box,
                  colour: object.colour,
                  spokenAs: object.spokenAs,
                ),
          ].where(hasPlausibleLargeClassArea).toList();
    final confirmed = _tracker.update(
      detections,
      requireCurrentDetection: true,
    );
    if (focused) {
      const centre = Offset(0.5, 0.5);
      if (confirmed.isNotEmpty) {
        return [
          confirmed.reduce(
            (a, b) =>
                (a.box.center - centre).distanceSquared <=
                    (b.box.center - centre).distanceSquared
                ? a
                : b,
          ),
        ];
      }
      // A cut-off candidate can be a consequence of Cue's own zoom. Check
      // the full view while there are still two passes to confirm the item.
      if (crop != null &&
          crop != _fullFrame &&
          _passes <= _maxPasses - _tracker.passesToConfirm &&
          seen.any(
            (object) =>
                !object.isAmbiguous &&
                isConfidentDetection(object) &&
                object.box.contains(centre) &&
                boxInFullFrame(object.box, crop) == null,
          )) {
        _region = _fullFrame;
        _tracker.reset();
      } else if (crop == _tighterCloseUp &&
          (_passes == 3 || (_passes == 2 && detections.isEmpty))) {
        _region = _closeUp;
      }
      return _passes == _maxPasses ? const [] : null;
    }
    final answer = crop == null
        ? confirmed.where((object) => !_needsCloseUp(object)).toList()
        : confirmed;
    if (answer.isNotEmpty || _passes == _maxPasses) return answer;

    if (crop == null &&
        _passes >= 2 &&
        (!_sawFullFrameCandidate || confirmed.isNotEmpty)) {
      _region = _closeUp;
    } else if (crop == _closeUp && detections.isEmpty) {
      _region = _tighterCloseUp;
    }
    return null;
  }

  bool _needsCloseUp(DetectedObject object) {
    if (object.confidence >= strictClassConfidence) return false;
    final interior = _closeUp.deflate(0.02);
    return interior.contains(object.box.topLeft) &&
        interior.contains(object.box.bottomRight);
  }
}

/// Requires an object to be seen more than once before Cue trusts it.
///
/// A single YOLO pass on a blank wall will occasionally invent a "person" or a
/// "tv". Speaking that is what makes the mode feel random to a blind user. An
/// object now has to survive [passesToConfirm] consecutive passes with the same
/// spoken label, and once trusted it stays trusted for [passesToForget] misses
/// so a nudge of the camera does not make a real chair disappear mid-sentence.
///
/// Matching on the spoken label, not the raw class, is deliberate. A comb that
/// flips to "knife" and back is one physical object; if both frames were
/// relabelled "small object", the track should continue as "small object"
/// rather than start again on every flicker.
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
    this.passesToConfirm = 3,
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
    bool requireCurrentDetection = false,
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
        if (track.object.label != detection.label) continue;

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
      // A direct answer needs a position from a frame that saw the object.
      if ((trustImmediately || requireCurrentDetection) &&
          !observed.contains(track.id)) {
        continue;
      }
      if (track.hits < needed) continue;
      confirmed.add(track.object);
    }

    // Nearest first: for walking, distance matters more than label order.
    confirmed.sort(_byImportance);
    return confirmed;
  }

  /// The identity of an object returned by the latest update.
  Object? identityOf(DetectedObject object) {
    for (final track in _tracks.values) {
      if (identical(track.object, object)) return track;
    }
    return null;
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
  _Track({required this.id, required this.object}) : lastSample = object.colour;

  ColourReading? lastSample;

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
      colour: next.colour?.colour == lastSample?.colour ? next.colour : null,
      // Certainty can improve or degrade between frames; the current frame's
      // label is the one the track is now matching on.
      spokenAs: next.spokenAs,
    );
    lastSample = next.colour;
    hits++;
    misses = 0;
  }
}

double _lerp(double from, double to, double alpha) =>
    from + (to - from) * alpha;
