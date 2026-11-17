import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:cue/live/object_box_painter.dart';
import 'package:cue/vision/detected_object.dart';

void main() {
  test('ObjectBoundingBoxesPainter paints empty list without error', () {
    const painter = ObjectBoundingBoxesPainter([]);
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, const Size(720, 1280));
    final picture = recorder.endRecording();
    expect(picture, isNotNull);
  });

  test(
    'ObjectBoundingBoxesPainter paints detected objects with confidence labels',
    () {
      const objects = [
        DetectedObject(
          name: 'person',
          confidence: 0.88,
          box: Rect.fromLTWH(0.1, 0.2, 0.4, 0.6),
        ),
        DetectedObject(
          name: 'car',
          confidence: 0.94,
          box: Rect.fromLTWH(0.5, 0.3, 0.4, 0.4),
        ),
      ];

      const painter = ObjectBoundingBoxesPainter(objects);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, const Size(720, 1280));
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    },
  );

  test('ObjectBoundingBoxesPainter shouldRepaint responds to changes', () {
    const obj1 = DetectedObject(
      name: 'cup',
      confidence: 0.75,
      box: Rect.fromLTWH(0.2, 0.2, 0.3, 0.3),
    );
    const obj2 = DetectedObject(
      name: 'cup',
      confidence: 0.82,
      box: Rect.fromLTWH(0.2, 0.2, 0.3, 0.3),
    );

    const painter1 = ObjectBoundingBoxesPainter([obj1]);
    const painter1Same = ObjectBoundingBoxesPainter([obj1]);
    const painter2 = ObjectBoundingBoxesPainter([obj2]);
    const painterEmpty = ObjectBoundingBoxesPainter([]);

    expect(painter1.shouldRepaint(painter1Same), isFalse);
    expect(painter1.shouldRepaint(painter2), isTrue);
    expect(painter1.shouldRepaint(painterEmpty), isTrue);
  });
}
