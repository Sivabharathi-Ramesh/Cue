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
