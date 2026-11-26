import 'dart:math' as math;
import 'dart:ui';

import '../core/personal_items.dart';
import '../core/search_target.dart';
import '../vision/detected_object.dart';
import '../vision/object_tracker.dart';

/// A single camera search. All positions are in the upright, uncropped frame.
class ItemSearch {
  ItemSearch(SearchTarget this.target, this.startedAt) : personalItem = null;
  ItemSearch.personal(PersonalItem this.personalItem, this.startedAt)
    : target = null;

  final SearchTarget? target;
  final PersonalItem? personalItem;
  final DateTime startedAt;

  static const _frameGap = Duration(milliseconds: 450);
  static const _evidenceLifetime = Duration(milliseconds: 2500);
  static const _verificationScoreMargin = 0.15;
  static const _strongPersonalScore = 0.75;
  static const _fullFrame = Rect.fromLTWH(0, 0, 1, 1);

  // Try wide views of close objects before looking at smaller overlapping
  // regions. Each pass uses a fresh frame and one model invocation.
  static const _regions = <Rect?>[
    null,
    Rect.fromLTRB(0.06, 0.10, 0.94, 0.90),
    Rect.fromLTRB(0, 0.15, 1, 0.85),
    Rect.fromLTRB(0.26, 0.26, 0.74, 0.74),
    Rect.fromLTRB(0, 0, 0.48, 0.48),
    Rect.fromLTRB(0.26, 0, 0.74, 0.48),
    Rect.fromLTRB(0.52, 0, 1, 0.48),
    Rect.fromLTRB(0, 0.26, 0.48, 0.74),
    Rect.fromLTRB(0.52, 0.26, 1, 0.74),
    Rect.fromLTRB(0, 0.52, 0.48, 1),
    Rect.fromLTRB(0.26, 0.52, 0.74, 1),
    Rect.fromLTRB(0.52, 0.52, 1, 1),
  ];

  final _tracker = ObjectTracker(
    passesToConfirm: 3,
    passesToForget: 2,
    smoothing: 1,
  );
  int _regionIndex = 0;
  int _passesInRegion = 0;
  int _misses = 0;
  int? _rotation;
  DateTime? _lastFrame;
  bool _gaveHint = false;
  bool _gaveCandidateHint = false;
  bool scanDetail = false;

  ({
    Rect region,
    Rect? retry,
    DetectedObject candidate,
    DateTime started,
    DateTime after,
    ObjectDirection? personalDirection,
  })?
  _verification;

  Rect? get region => _verification?.region ?? _regions[_regionIndex];
  bool get isVerifying => _verification != null;

  bool ready(DateTime now) {
    final last = _lastFrame;
    return last == null || now.difference(last) >= _frameGap;
  }

  void beginFrame(DateTime now, int rotation) {
    final last = _verification?.started ?? _lastFrame;
    if (_rotation != rotation ||
        (last != null && now.difference(last) > _evidenceLifetime)) {
      _regionIndex = 0;
      scanDetail = false;
      _resetRegion();
    }
    _rotation = rotation;
    _lastFrame = now;
  }

  /// Confirms a target only when fresh frames agree on the same position.
  ({
    List<DetectedObject> candidates,
    DetectedObject? match,
    ObjectDirection? personalDirection,
  })
  observe(
    List<DetectedObject> detections, {
    ObjectDirection? personalDirection,
  }) {
    final verification = _verification;
    final capturedAt = _lastFrame ?? startedAt;
    if (verification != null && !capturedAt.isAfter(verification.after)) {
      return (candidates: const [], match: null, personalDirection: null);
    }
    final window = region ?? _fullFrame;
    final inFrame = <DetectedObject>[];
    final builtIn = target;
    for (final object in detections) {
      if (builtIn != null
          ? !isSearchCandidate(object, builtIn)
          : object.name != personalItem!.name) {
        continue;
      }
      // A taught-item check scores the whole crop as one feature window.
      final box = verification != null && personalItem != null
          ? window
          : boxInFullFrame(object.box, window);
      if (box == null) continue;
      inFrame.add(
        DetectedObject(
          name: builtIn?.labels.first ?? object.name,
          confidence: object.confidence,
          box: box,
        ),
      );
    }

    if (verification != null) {
      final matches = inFrame.where(
        (object) => boxIou(object.box, verification.candidate.box) >= 0.35,
      );
      if (matches.isEmpty) {
        if (verification.retry case final retry?) {
          _verification = (
            region: retry,
            retry: null,
            candidate: verification.candidate,
            started: verification.started,
            after: capturedAt,
            personalDirection: verification.personalDirection,
          );
        } else if (builtIn != null) {
          _nextRegion();
        } else {
          scanDetail = !scanDetail;
          _resetRegion();
        }
        return (candidates: const [], match: null, personalDirection: null);
      }
      final match = matches.reduce(_higherConfidence);
      _resetRegion();
      return (
        candidates: inFrame,
        match: match,
        personalDirection: match.direction == verification.personalDirection
            ? verification.personalDirection
            : null,
      );
    }

    final confirmed = _tracker.update(inFrame, requireCurrentDetection: true);
    if (confirmed.isNotEmpty) {
      final match = confirmed.reduce(_higherConfidence);
      final crop = _verificationCrop(match, window);
      if (crop == null) {
        return (
          candidates: inFrame,
          match: match,
          personalDirection: personalDirection,
        );
      }
      final retry = builtIn == null
          ? null
          : _verificationCrop(match, window, minimumScale: 0.83);
      _verification = (
        region: crop,
        retry: retry == crop ? null : retry,
        candidate: match,
        started: capturedAt,
        after: capturedAt,
        personalDirection: personalDirection,
      );
      return (candidates: inFrame, match: null, personalDirection: null);
    }

    _passesInRegion++;
    _misses = inFrame.isEmpty ? _misses + 1 : 0;
    if (personalItem != null && inFrame.isEmpty) scanDetail = !scanDetail;
    if (builtIn?.needsDetail == true &&
        (_passesInRegion == 4 ||
            _misses == 2 ||
            (_passesInRegion == 1 && _misses == 1))) {
      _nextRegion();
    }
    return (candidates: inFrame, match: null, personalDirection: null);
  }

  Rect? _verificationCrop(
    DetectedObject candidate,
    Rect view, {
    double minimumScale = 0.65,
  }) {
    final builtIn = target;
    final box = candidate.box;
    if (builtIn == null) {
      if (candidate.confidence >= _strongPersonalScore) return null;
      return Rect.fromCenter(
        center: box.center,
        width: box.width * 0.75,
        height: box.height * 0.75,
      );
    }
    if (!builtIn.needsDetail ||
        candidate.confidence >=
            searchCandidateConfidence(builtIn) + _verificationScoreMargin) {
      return null;
    }

    // Check small boxes that fit in a closer view with room around them.
    final coverage = math.max(box.width / view.width, box.height / view.height);
    final scale = math.max(minimumScale, coverage * 1.25);
    if (scale > 0.85) return null;
    final width = view.width * scale;
    final height = view.height * scale;
    return Rect.fromLTWH(
      (box.center.dx - width / 2).clamp(0.0, 1 - width),
      (box.center.dy - height / 2).clamp(0.0, 1 - height),
      width,
      height,
    );
  }

  static DetectedObject _higherConfidence(DetectedObject a, DetectedObject b) =>
      a.confidence >= b.confidence ? a : b;

  bool takeHint(DateTime now) {
    if (_gaveHint || now.difference(startedAt) < const Duration(seconds: 7)) {
      return false;
    }
    _gaveHint = true;
    return true;
  }

  bool takeCandidateHint() {
    if (_gaveCandidateHint) return false;
    _gaveCandidateHint = true;
    return true;
  }

  void _nextRegion() {
    _regionIndex = (_regionIndex + 1) % _regions.length;
    _resetRegion();
  }

  void _resetRegion() {
    _verification = null;
    _tracker.reset();
    _passesInRegion = 0;
    _misses = 0;
  }
}
