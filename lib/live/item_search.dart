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
  bool scanDetail = false;

  Rect? get region => _regions[_regionIndex];

  bool ready(DateTime now) {
    final last = _lastFrame;
    return last == null || now.difference(last) >= _frameGap;
  }

  void beginFrame(DateTime now, int rotation) {
    final last = _lastFrame;
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
  ({List<DetectedObject> candidates, DetectedObject? match}) observe(
    List<DetectedObject> detections,
  ) {
    final window = region ?? _fullFrame;
    final inFrame = <DetectedObject>[];
    final builtIn = target;
    for (final object in detections) {
      if (builtIn != null
          ? !isSearchCandidate(object, builtIn)
          : object.name != personalItem!.name) {
        continue;
      }
      final box = object.box.intersect(_fullFrame);
      if (box.isEmpty || _cutByCrop(box, window)) continue;
      inFrame.add(
        DetectedObject(
          name: builtIn?.labels.first ?? object.name,
          confidence: object.confidence,
          box: Rect.fromLTWH(
            window.left + box.left * window.width,
            window.top + box.top * window.height,
            box.width * window.width,
            box.height * window.height,
          ),
        ),
      );
    }

    final confirmed = _tracker.update(inFrame, requireCurrentDetection: true);
    if (confirmed.isNotEmpty) {
      final match = confirmed.reduce(
        (a, b) => a.confidence >= b.confidence ? a : b,
      );
      return (candidates: inFrame, match: match);
    }

    _passesInRegion++;
    _misses = inFrame.isEmpty ? _misses + 1 : 0;
    if (personalItem != null && inFrame.isEmpty) scanDetail = !scanDetail;
    if (builtIn?.needsDetail == true &&
        (_passesInRegion == 4 ||
            _misses == 2 ||
            (_passesInRegion == 1 && _misses == 1))) {
      _regionIndex = (_regionIndex + 1) % _regions.length;
      _resetRegion();
    }
    return (candidates: inFrame, match: null);
  }

  bool takeHint(DateTime now) {
    if (_gaveHint || now.difference(startedAt) < const Duration(seconds: 7)) {
      return false;
    }
    _gaveHint = true;
    return true;
  }

  void _resetRegion() {
    _tracker.reset();
    _passesInRegion = 0;
    _misses = 0;
  }

  /// A box on an internal boundary may only contain part of the item.
  bool _cutByCrop(Rect box, Rect window) =>
      (window.left > 0 && box.left <= 0.01) ||
      (window.top > 0 && box.top <= 0.01) ||
      (window.right < 1 && box.right >= 0.99) ||
      (window.bottom < 1 && box.bottom >= 0.99);
}
