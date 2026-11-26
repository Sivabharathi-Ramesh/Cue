import 'dart:ui';

import 'package:cue/core/search_target.dart';
import 'package:cue/live/item_search.dart';
import 'package:cue/vision/detected_object.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime(2026);

DetectedObject _detection(
  Rect box, {
  String name = 'keys',
  double score = 0.48,
}) => DetectedObject(name: name, confidence: score, box: box);

DetectedObject? _observe(
  ItemSearch search,
  int frame,
  List<DetectedObject> detections, {
  int rotation = 0,
}) {
  search.beginFrame(_start.add(Duration(milliseconds: frame * 500)), rotation);
  return search.observe(detections).match;
}

Rect _inCrop(Rect box, Rect crop) => Rect.fromLTWH(
  (box.left - crop.left) / crop.width,
  (box.top - crop.top) / crop.height,
  box.width / crop.width,
  box.height / crop.height,
);

void main() {
  const smallKey = Rect.fromLTWH(0.73, 0.53, 0.043, 0.017);

  test('confirms a small, moderate-confidence key after one missed frame', () {
    final search = ItemSearch(SearchTarget.keys, _start);
    final key = _detection(smallKey);
    expect(_observe(search, 0, [key]), isNull);
    expect(_observe(search, 1, []), isNull);
    expect(_observe(search, 2, [key]), isNull);
    final found = _observe(search, 3, [key]);
    expect(found?.direction, ObjectDirection.right);
    expect(found?.box.left, closeTo(smallKey.left, 0.000001));
  });

  test('tries a wide view when a close key fills much of the frame', () {
    final search = ItemSearch(SearchTarget.keys, _start);
    _observe(search, 0, []);
    expect(search.region, const Rect.fromLTRB(0.06, 0.10, 0.94, 0.90));
    final closeKey = _detection(const Rect.fromLTRB(0.11, 0.22, 0.91, 0.83));
    expect(_observe(search, 1, [closeKey]), isNull);
    expect(_observe(search, 2, [closeKey]), isNull);
    final found = _observe(search, 3, [closeKey]);
    expect(found?.direction, ObjectDirection.ahead);
    expect(found?.box.width, closeTo(0.704, 0.000001));
  });

  test('enlarges parts of the view after wider misses and maps them back', () {
    final search = ItemSearch(SearchTarget.keys, _start);
    expect(search.region, isNull);
    _observe(search, 0, []);
    _observe(search, 1, []);
    _observe(search, 2, []);
    expect(search.region, const Rect.fromLTRB(0.26, 0.26, 0.74, 0.74));
    _observe(search, 3, []);
    _observe(search, 4, []);
    _observe(search, 5, []);
    expect(search.region, const Rect.fromLTRB(0.52, 0, 1, 0.48));
    final key = _detection(const Rect.fromLTWH(0.51, 0.4, 0.12, 0.08));
    search.beginFrame(_start.add(const Duration(seconds: 3)), 0);
    final first = search.observe([key]);
    expect(first.match, isNull);
    expect(first.candidates.single.box.left, closeTo(0.7648, 0.000001));
    expect(_observe(search, 7, [key]), isNull);
    final found = _observe(search, 8, [key]);
    expect(found?.direction, ObjectDirection.right);
    expect(found?.box.left, closeTo(0.7648, 0.000001));
  });

  test('discards boxes cut off at an internal crop boundary', () {
    final search = ItemSearch(SearchTarget.keys, _start);
    _observe(search, 0, []);
    final partial = _detection(const Rect.fromLTWH(0, 0.4, 0.1, 0.09));
    expect(_observe(search, 1, [partial]), isNull);
    expect(search.region, const Rect.fromLTRB(0, 0.15, 1, 0.85));
  });

  test('discards stale evidence and evidence from a different orientation', () {
    final search = ItemSearch(SearchTarget.keys, _start);
    final key = _detection(smallKey);
    _observe(search, 0, [key]);
    _observe(search, 1, [key]);
    expect(_observe(search, 7, [key]), isNull);
    _observe(search, 8, [key]);
    expect(_observe(search, 9, [key], rotation: 90), isNull);
  });

  test('keeps separate locations and unrelated labels out of confirmation', () {
    final search = ItemSearch(SearchTarget.keys, _start);
    final left = _detection(const Rect.fromLTWH(0.2, 0.5, 0.06, 0.04));
    final right = _detection(smallKey);
    expect(_observe(search, 0, [left]), isNull);
    expect(_observe(search, 1, [right]), isNull);
    expect(_observe(search, 2, [left]), isNull);
    expect(_observe(search, 3, [_detection(smallKey, name: 'pen')]), isNull);
  });

  test('a borderline key confirms only in a fresh, closer view', () {
    final search = ItemSearch(SearchTarget.keys, _start);
    final key = _detection(smallKey, score: 0.30);
    for (var frame = 0; frame < 3; frame++) {
      expect(_observe(search, frame, [key]), isNull);
    }
    final crop = search.region!;
    expect(search.isVerifying, isTrue);
    expect(crop.width, lessThan(1));
    expect(crop.contains(smallKey.center), isTrue);
    final closer = _detection(_inCrop(smallKey, crop), score: 0.34);
    expect(search.observe([closer]).match, isNull);
    final confirmed = _observe(search, 3, [closer])!;
    expect(confirmed.direction, ObjectDirection.right);
    expect(confirmed.box.left, closeTo(smallKey.left, 0.000001));
    expect(search.isVerifying, isFalse);
  });

  test('different boxes in both verification crops restart the search', () {
    final search = ItemSearch(SearchTarget.keys, _start);
    final key = _detection(smallKey, score: 0.30);
    for (var frame = 0; frame < 3; frame++) {
      _observe(search, frame, [key]);
    }
    final different = _detection(
      const Rect.fromLTWH(0.12, 0.31, 0.10, 0.05),
      score: 0.90,
    );
    expect(_observe(search, 3, [different]), isNull);
    expect(search.isVerifying, isTrue);
    expect(search.observe([different]).match, isNull);
    expect(_observe(search, 4, [different]), isNull);
    expect(search.isVerifying, isFalse);
    final normalCrop = search.region!;
    final returnedKey = _detection(_inCrop(smallKey, normalCrop));
    expect(_observe(search, 5, [returnedKey]), isNull);
    expect(_observe(search, 6, [returnedKey]), isNull);
    expect(_observe(search, 7, [returnedKey])?.name, 'keys');
  });

  test('tries a wider close-up when the tight view loses a weak key', () {
    final search = ItemSearch(SearchTarget.keys, _start);
    final weak = _detection(smallKey, score: 0.30);
    for (var i = 0; i < 3; i++) {
      _observe(search, i, [weak]);
    }
    final tight = search.region!;
    expect(_observe(search, 3, []), isNull);
    final wider = search.region!;
    expect(wider.width, inExclusiveRange(tight.width, 1));
    final zoomed = _detection(_inCrop(smallKey, wider), score: 0.32);
    final found = _observe(search, 4, [zoomed])!;
    expect(found.box.left, closeTo(smallKey.left, 0.000001));
    expect(found.direction, ObjectDirection.right);
  });

  test('rotation and age discard a pending closer view', () {
    for (final (frame, rotation) in [(3, 90), (8, 0)]) {
      final search = ItemSearch(SearchTarget.keys, _start);
      final weakKey = _detection(smallKey, score: 0.30);
      for (var i = 0; i < 3; i++) {
        _observe(search, i, [weakKey]);
      }
      expect(search.isVerifying, isTrue);
      expect(_observe(search, frame, [weakKey], rotation: rotation), isNull);
      expect(search.isVerifying, isFalse);
      expect(search.region, isNull);
    }
  });

  test('supports label aliases across frames in a full-frame search', () {
    final search = ItemSearch(SearchTarget.bottle, _start);
    const box = Rect.fromLTWH(0.47, 0.46, 0.08, 0.15);
    final bottle = _detection(box, name: 'bottle');
    final waterBottle = _detection(box, name: 'water bottle');
    _observe(search, 0, []);
    expect(search.region, isNull);
    _observe(search, 1, [bottle]);
    _observe(search, 2, [waterBottle]);
    expect(_observe(search, 3, [bottle])?.name, 'bottle');
  });
}
