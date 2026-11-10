import 'dart:ui';

import 'package:cue/core/object_labels.dart';
import 'package:cue/vision/detected_object.dart';
import 'package:cue/vision/object_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

DetectedObject objectAt(
  String name, {
  double confidence = 0.9,
  double left = 0.4,
  double top = 0.3,
  double width = 0.2,
  double height = 0.4,
}) {
  return DetectedObject(
    name: name,
    confidence: confidence,
    box: Rect.fromLTWH(left, top, width, height),
  );
}

void main() {
  group('DetectedObject', () {
    test('a box on the left is reported to the left', () {
      final object = objectAt('chair', left: 0.05, width: 0.2);
      expect(object.direction, ObjectDirection.left);
    });

    test('a centred box is reported ahead', () {
      final object = objectAt('chair', left: 0.4, width: 0.2);
      expect(object.direction, ObjectDirection.ahead);
    });

    test('a box on the right is reported to the right', () {
      final object = objectAt('chair', left: 0.75, width: 0.2);
      expect(object.direction, ObjectDirection.right);
    });

    test('a person filling half the frame is about three metres away', () {
      final person = objectAt('person', height: 0.6);
      final distance = person.distanceMeters;
      expect(distance, isNotNull);
      expect(distance!, closeTo(2.98, 0.1));
      expect(englishDistancePhrase(distance), 'about 3 metres away');
    });

    test('a close bottle reads as about a metre', () {
      final bottle = objectAt('bottle', width: 0.1, height: 0.26);
      expect(
        englishDistancePhrase(bottle.distanceMeters),
        'about a metre away',
      );
    });

    test('flat classes have no honest distance estimate', () {
      final pizza = objectAt('pizza', height: 0.2);
      expect(pizza.distanceMeters, isNull);
    });

    test('a box that fills the whole frame still estimates, clamped', () {
      final wall = objectAt('car', height: 1.0);
      expect(wall.distanceMeters, closeTo(1.575, 0.01));
    });
  });

  group('objectDescription', () {
    test('names the object, its distance and its direction in English', () {
      final chair = objectAt('chair', height: 0.45, left: 0.05, width: 0.2);
      expect(
        objectDescription([chair], hindi: false),
        'Chair, about 2 metres away, to your left.',
      );
    });

    test('says "in front of you" for a central object', () {
      final chair = objectAt('chair', height: 0.45, left: 0.4, width: 0.2);
      expect(
        objectDescription([chair], hindi: false),
        'Chair, about 2 metres away in front of you.',
      );
    });

    test('omits distance when there is no honest estimate', () {
      final pizza = objectAt('pizza', left: 0.75, width: 0.2);
      expect(objectDescription([pizza], hindi: false), 'Pizza, to your right.');
    });

    test('uses Hindi labels and word order when the app is in Hindi', () {
      final chair = objectAt('chair', height: 0.45, left: 0.05, width: 0.2);
      final text = objectDescription([chair], hindi: true);
      expect(text, contains('कुर्सी'));
      expect(text, contains('आपके बाईं ओर'));
      expect(text, contains('मीटर'));
    });

    test('describes several objects one after another', () {
      final chair = objectAt('chair', height: 0.45);
      final bottle = objectAt('bottle', left: 0.7, width: 0.08, height: 0.3);
      final text = objectDescription([chair, bottle], hindi: false);
      expect(text, contains('Chair'));
      expect(text, contains('Bottle'));
    });

    test('says nothing for an empty list', () {
      expect(objectDescription(const [], hindi: false), '');
    });
  });

  group('isConfidentDetection', () {
    test('a normal object at sixty percent is spoken', () {
      expect(
        isConfidentDetection(
          objectAt('chair', confidence: 0.60),
          lenient: false,
        ),
        isTrue,
      );
    });

    test('a normal object below the bar is not', () {
      expect(
        isConfidentDetection(
          objectAt('chair', confidence: 0.59),
          lenient: false,
        ),
        isFalse,
      );
    });

    test('a risky class at seventy percent is not spoken', () {
      expect(
        isConfidentDetection(
          objectAt('carrot', confidence: 0.70),
          lenient: false,
        ),
        isFalse,
      );
    });

    test('a risky class at eighty percent is spoken', () {
      expect(
        isConfidentDetection(
          objectAt('carrot', confidence: 0.80),
          lenient: false,
        ),
        isTrue,
      );
    });

    test('a manual request lowers the bar for ordinary objects', () {
      expect(
        isConfidentDetection(
          objectAt('chair', confidence: 0.55),
          lenient: true,
        ),
        isTrue,
      );
    });

    test('a risky class below the strict confidence is silent', () {
      expect(
        isConfidentDetection(
          objectAt('mobile phone', confidence: 0.65),
          lenient: false,
        ),
        isFalse,
      );
    });

    test('a strict class above the confidence is spoken', () {
      expect(
        isConfidentDetection(
          objectAt('mobile phone', confidence: 0.80),
          lenient: false,
        ),
        isTrue,
      );
    });

    test('a huge appliance below the frame-area floor is rejected', () {
      final refrigerator = objectAt(
        'refrigerator',
        confidence: 0.95,
        width: 0.1,
        height: 0.1,
      );
      expect(hasPlausibleLargeClassArea(refrigerator), isFalse);

      final visibleRefrigerator = objectAt(
        'refrigerator',
        width: 0.3,
        height: 0.35,
      );
      expect(hasPlausibleLargeClassArea(visibleRefrigerator), isTrue);
    });

    test('a manual request still refuses a weak risky label', () {
      expect(
        isConfidentDetection(
          objectAt('carrot', confidence: 0.62),
          lenient: true,
        ),
        isFalse,
      );
    });

    test('pen is not a COCO class, so a desk label must stay silent', () {
      expect(
        isConfidentDetection(
          objectAt('carrot', confidence: 0.66),
          lenient: false,
        ),
        isFalse,
      );
    });
  });

  group('ObjectTracker', () {
    test('waits for two passes before trusting an object', () {
      final tracker = ObjectTracker();
      final chair = objectAt('chair');

      expect(tracker.update([chair]), isEmpty);
      expect(tracker.update([chair]), hasLength(1));
    });

    test('a manual request answers on the first pass', () {
      final tracker = ObjectTracker();
      final chair = objectAt('chair');

      final confirmed = tracker.update([chair], trustImmediately: true);
      expect(confirmed, hasLength(1));
    });

    test('a one-frame hallucination never surfaces', () {
      final tracker = ObjectTracker();
      final ghost = objectAt('person');

      tracker.update([ghost]);
      tracker.update(const []);
      expect(tracker.update(const []), isEmpty);
    });

    test('a real object survives a single missed pass', () {
      final tracker = ObjectTracker();
      final chair = objectAt('chair');

      tracker.update([chair]);
      tracker.update([chair]);
      expect(tracker.update(const []), hasLength(1));
      expect(tracker.update(const []), isEmpty);
    });

    test('keeps one box per class, preferring the confident one', () {
      final tracker = ObjectTracker();
      final weak = objectAt('chair', confidence: 0.5);
      final strong = objectAt('chair', confidence: 0.9, left: 0.1);

      tracker.update([weak, strong]);
      final confirmed = tracker.update([weak, strong]);

      expect(confirmed, hasLength(1));
      expect(confirmed.single.confidence, 0.9);
      expect(confirmed.single.direction, ObjectDirection.left);
    });

    test('nearest object is listed first', () {
      final tracker = ObjectTracker()
        ..update([
          objectAt('person', height: 0.2),
          objectAt('cup', left: 0.1, width: 0.1, height: 0.4),
        ]);

      final confirmed = tracker.update([
        objectAt('person', height: 0.2),
        objectAt('cup', left: 0.1, width: 0.1, height: 0.4),
      ]);

      expect(confirmed.first.name, 'cup');
    });

    test('reset forgets everything', () {
      final tracker = ObjectTracker();
      tracker.update([objectAt('chair')]);
      tracker.update([objectAt('chair')]);

      tracker.reset();

      expect(tracker.update([objectAt('chair')]), isEmpty);
    });
  });
}
