import 'dart:ui';

import 'package:cue/core/object_labels.dart';
import 'package:cue/vision/detected_object.dart';
import 'package:cue/vision/object_colour.dart';
import 'package:cue/vision/object_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

DetectedObject objectAt(
  String name, {
  double confidence = 0.9,
  double left = 0.4,
  double top = 0.3,
  double width = 0.2,
  double height = 0.4,
  ColourReading? colour,
  String? spokenAs,
}) {
  return DetectedObject(
    name: name,
    confidence: confidence,
    box: Rect.fromLTWH(left, top, width, height),
    colour: colour,
    spokenAs: spokenAs,
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

    test('a person filling half the frame is a couple of metres away', () {
      final person = objectAt('person', height: 0.6);
      final distance = person.distanceMeters;
      expect(distance, isNotNull);
      expect(distance!, closeTo(2.98, 0.1));
      expect(englishDistancePhrase(distance), 'a couple of metres away');
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

    test('thin and flat everyday classes have no honest distance', () {
      // Their box height is thickness, not length. The old table borrowed a
      // knife's height for a comb and reported metres that were pure fiction.
      for (final name in ['comb', 'marker', 'pen', 'knife', 'notebook']) {
        expect(
          objectAt(name, height: 0.3).distanceMeters,
          isNull,
          reason: '$name must not get a bounding-box distance',
        );
      }
    });

    test('a tiny box far away is refused rather than guessed', () {
      final bottle = objectAt('bottle', height: 0.031);
      expect(bottle.distanceMeters, isNull);
    });

    test('a cropped box gets no numeric distance', () {
      final chair = objectAt('chair', top: 0.0, height: 1.0);
      expect(chair.isVerticallyCropped, isTrue);
      expect(chair.distanceMeters, isNull);
      expect(englishObjectDistancePhrase(chair), 'partly out of view');
    });

    test('distance is spoken in honest bands, not false precision', () {
      expect(englishDistancePhrase(0.4), 'very close');
      expect(englishDistancePhrase(1.0), 'about a metre away');
      expect(englishDistancePhrase(2.1), 'a couple of metres away');
      expect(englishDistancePhrase(4.0), 'several metres away');
      expect(englishDistancePhrase(8.0), 'across the room');
      expect(englishDistancePhrase(14.0), 'far away');
    });
  });

  group('resolveObjectAmbiguity', () {
    test('a comb and a knife on one box become a small object', () {
      final comb = objectAt('comb', confidence: 0.80);
      final knife = objectAt('knife', confidence: 0.70);
      final resolved = resolveObjectAmbiguity(comb, [comb, knife]);

      expect(resolved.isAmbiguous, isTrue);
      expect(resolved.label, 'small object');
      expect(resolved.name, 'comb');
      expect(resolved.distanceMeters, isNull);
    });

    test('a clear winner keeps its name', () {
      final comb = objectAt('comb', confidence: 0.92);
      final knife = objectAt('knife', confidence: 0.62);
      final resolved = resolveObjectAmbiguity(comb, [comb, knife]);

      expect(resolved.isAmbiguous, isFalse);
      expect(resolved.label, 'comb');
    });

    test('candidates in the same family keep the family name', () {
      final comb = objectAt('comb', confidence: 0.80);
      final brush = objectAt('hairbrush', confidence: 0.72);
      expect(
        resolveObjectAmbiguity(comb, [comb, brush]).label,
        'grooming item',
      );

      final marker = objectAt('marker', confidence: 0.80);
      final pen = objectAt('pen', confidence: 0.74);
      expect(
        resolveObjectAmbiguity(marker, [marker, pen]).label,
        'writing tool',
      );

      final knife = objectAt('knife', confidence: 0.80);
      final fork = objectAt('fork', confidence: 0.72);
      expect(resolveObjectAmbiguity(knife, [knife, fork]).label, 'utensil');
    });

    test('a competing box elsewhere in the frame is ignored', () {
      final comb = objectAt('comb', confidence: 0.80, left: 0.1);
      final knife = objectAt('knife', confidence: 0.78, left: 0.7);
      final resolved = resolveObjectAmbiguity(comb, [comb, knife]);

      expect(resolved.isAmbiguous, isFalse);
      expect(resolved.label, 'comb');
    });

    test('a non-confusable class is never relabelled', () {
      final chair = objectAt('chair', confidence: 0.80);
      final table = objectAt('table', confidence: 0.78);
      expect(
        resolveObjectAmbiguity(chair, [chair, table]).isAmbiguous,
        isFalse,
      );
    });
  });

  group('objectDescription', () {
    test('names the object, its distance and its direction in English', () {
      final chair = objectAt('chair', height: 0.45, left: 0.05, width: 0.2);
      expect(
        objectDescription([chair], hindi: false),
        'Chair, a couple of metres away, to your left.',
      );
    });

    test('says "in front of you" for a central object', () {
      final chair = objectAt('chair', height: 0.45, left: 0.4, width: 0.2);
      expect(
        objectDescription([chair], hindi: false),
        'Chair, a couple of metres away, in front of you.',
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

    test('groups identical objects into one counted sentence', () {
      final first = objectAt('chair', height: 0.45, left: 0.05, width: 0.2);
      final second = objectAt('chair', height: 0.45, left: 0.05, width: 0.2);

      expect(
        objectDescription([first, second], hindi: false),
        'Two chairs, a couple of metres away, to your left.',
      );
    });

    test('an ambiguous object is never given a confident name', () {
      final comb = objectAt('comb', confidence: 0.8, spokenAs: 'small object');
      final text = objectDescription([comb], hindi: false);

      expect(text, contains('Small object'));
      expect(text, isNot(contains('Comb')));
      expect(text, isNot(contains('Knife')));
    });

    test(
      'ambiguous objects are omitted in Hindi rather than named in English',
      () {
        final comb = objectAt(
          'comb',
          confidence: 0.8,
          spokenAs: 'small object',
        );
        expect(objectDescription([comb], hindi: true), isEmpty);
      },
    );

    test('a cropped object explains why there is no distance', () {
      final chair = objectAt('chair', top: 0.0, height: 1.0);
      expect(
        objectDescription([chair], hindi: false),
        'Chair, partly out of view, in front of you.',
      );
    });

    test('keeps differently coloured objects separate', () {
      final red = objectAt(
        'mug',
        height: 0.2,
        left: 0.05,
        width: 0.2,
        colour: const ColourReading(ObjectColour.red),
      );
      final blue = objectAt(
        'mug',
        height: 0.2,
        left: 0.05,
        width: 0.2,
        colour: const ColourReading(ObjectColour.blue),
      );

      final text = objectDescription([red, blue], hindi: false);
      expect(text, contains('Red mug'));
      expect(text, contains('Blue mug'));
      expect(text, isNot(contains('Two mugs')));
    });

    test('never describes a person by skin colour', () {
      final person = objectAt(
        'person',
        height: 0.6,
        colour: const ColourReading(ObjectColour.brown),
      );

      final text = objectDescription([person], hindi: false);
      expect(text, contains('Person'));
      expect(text, isNot(contains('brown')));

      final hindi = objectDescription([person], hindi: true);
      expect(hindi, isNot(contains('भूरा')));
    });

    test('uses the irregular plural for people', () {
      final first = objectAt('person', height: 0.5);
      final second = objectAt('person', height: 0.5);

      expect(
        objectDescription([first, second], hindi: false),
        contains('Two people'),
      );
    });

    test('says nothing for an empty list', () {
      expect(objectDescription(const [], hindi: false), '');
    });
  });

  group('englishPluralObjectLabel', () {
    test('handles regular and sibilant endings', () {
      expect(englishPluralObjectLabel('chair', 2), 'chairs');
      expect(englishPluralObjectLabel('box', 2), 'boxes');
      expect(englishPluralObjectLabel('glass', 2), 'glasses');
      expect(englishPluralObjectLabel('notebook', 2), 'notebooks');
    });

    test('leaves labels that are already plural alone', () {
      expect(englishPluralObjectLabel('keys', 2), 'keys');
      expect(englishPluralObjectLabel('headphones', 2), 'headphones');
    });

    test('knows the irregulars the model can emit', () {
      expect(englishPluralObjectLabel('person', 2), 'people');
      expect(englishPluralObjectLabel('computer mouse', 2), 'computer mice');
      expect(englishPluralObjectLabel('bookshelf', 2), 'bookshelves');
    });

    test('a count of one keeps the singular', () {
      expect(englishPluralObjectLabel('chair', 1), 'chair');
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

    test('an ambiguous box can be spoken as a group at the ordinary bar', () {
      final ambiguous = objectAt(
        'comb',
        confidence: 0.65,
        spokenAs: 'small object',
      );
      expect(isConfidentDetection(ambiguous, lenient: false), isTrue);
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

    test('a small stationery class needs the strict bar', () {
      expect(
        isConfidentDetection(objectAt('pen', confidence: 0.70), lenient: false),
        isFalse,
      );
      expect(
        isConfidentDetection(objectAt('pen', confidence: 0.80), lenient: false),
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
    test('waits for three passes before trusting an object', () {
      final tracker = ObjectTracker();
      final chair = objectAt('chair');

      expect(tracker.update([chair]), isEmpty);
      expect(tracker.update([chair]), isEmpty);
      expect(tracker.update([chair]), hasLength(1));
    });

    test('a manual request answers on the first pass', () {
      final tracker = ObjectTracker();
      final chair = objectAt('chair');

      final confirmed = tracker.update([chair], trustImmediately: true);
      expect(confirmed, hasLength(1));
    });

    test('a manual request does not repeat a stale position', () {
      final tracker = ObjectTracker();
      final left = objectAt('chair', left: 0.1, height: 0.4);
      final right = objectAt('chair', left: 0.7, height: 0.4);

      tracker.update([left]);
      tracker.update([left]);

      // The chair is now on the other side of the view. A manual answer
      // should describe the chair where it is, not both the old and new box.
      final confirmed = tracker.update([right], trustImmediately: true);
      expect(confirmed, hasLength(1));
      expect(confirmed.single.direction, ObjectDirection.right);
    });

    test('a manual request on an empty frame stays empty', () {
      final tracker = ObjectTracker();
      final chair = objectAt('chair');

      tracker.update([chair]);
      tracker.update([chair]);

      // Bridging keeps a live narration stable through one missed pass, but
      // "what is this?" asked now must answer about now, not about the chair
      // that was there a moment ago.
      expect(tracker.update(const [], trustImmediately: true), isEmpty);
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
      tracker.update([chair]);
      expect(tracker.update(const []), hasLength(1));
      expect(tracker.update(const []), isEmpty);
    });

    test('two separate boxes of the same class are two instances', () {
      final tracker = ObjectTracker();
      final left = objectAt('chair', confidence: 0.5, left: 0.1);
      final right = objectAt('chair', confidence: 0.9, left: 0.5);

      tracker.update([left, right]);
      tracker.update([left, right]);
      final confirmed = tracker.update([left, right]);

      expect(confirmed, hasLength(2));
      expect(confirmed.every((object) => object.name == 'chair'), isTrue);
    });

    test('overlapping boxes from one thing stay one instance', () {
      final tracker = ObjectTracker();
      final box = objectAt('chair', confidence: 0.7, left: 0.2, width: 0.2);
      final sameBox = objectAt(
        'chair',
        confidence: 0.9,
        left: 0.21,
        width: 0.2,
      );

      tracker.update([box, sameBox]);
      tracker.update([box, sameBox]);
      final confirmed = tracker.update([box, sameBox]);

      expect(confirmed, hasLength(1));
      expect(confirmed.single.confidence, greaterThan(0.8));
    });

    test('a jittering box is matched, not duplicated', () {
      final tracker = ObjectTracker();
      final first = objectAt('chair', left: 0.4, width: 0.2, height: 0.45);
      final jitter = objectAt('chair', left: 0.415, width: 0.2, height: 0.44);

      tracker.update([first]);
      tracker.update([first]);
      final confirmed = tracker.update([jitter]);

      expect(confirmed, hasLength(1));
      expect(
        englishDistancePhrase(confirmed.single.distanceMeters),
        'a couple of metres away',
      );
    });

    test('a moved object keeps its instance instead of starting again', () {
      final tracker = ObjectTracker();
      final first = objectAt('chair', left: 0.4, height: 0.45);
      final moved = objectAt('chair', left: 0.46, height: 0.45);

      tracker.update([first]);
      tracker.update([first]);
      expect(tracker.update([moved]), hasLength(1));
    });

    test('a sudden size change starts a new instance', () {
      final tracker = ObjectTracker();
      final near = objectAt('chair', height: 0.6);
      final far = objectAt('chair', height: 0.15);

      tracker.update([near]);
      tracker.update([near]);
      tracker.update([near]);

      // A box six times smaller is not the same chair moving a little. The
      // old track is still bridged this pass, but the new box is not trusted
      // until it has been seen three times.
      final old = tracker.update([far]);
      expect(old, hasLength(1));
      expect(old.single.distanceMeters, closeTo(1.575, 0.1));

      expect(tracker.update([far]), isEmpty);
      final fresh = tracker.update([far]);
      expect(fresh, hasLength(1));
      expect(fresh.single.distanceMeters, closeTo(6.3, 0.2));
    });

    test('nearest object is listed first', () {
      final tracker = ObjectTracker()
        ..update([
          objectAt('person', height: 0.2),
          objectAt('cup', left: 0.1, width: 0.1, height: 0.4),
        ])
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
      tracker.update([objectAt('chair')]);

      tracker.reset();

      expect(tracker.update([objectAt('chair')]), isEmpty);
    });

    test('a label that flips between passes is not trusted', () {
      final tracker = ObjectTracker();
      final comb = objectAt('comb');
      final knife = objectAt('knife');

      expect(tracker.update([comb]), isEmpty);
      expect(tracker.update([knife]), isEmpty);
      expect(tracker.update([comb]), isEmpty);
      expect(tracker.update([knife]), isEmpty);
    });

    test('an ambiguous label stays one track across raw-class flips', () {
      final tracker = ObjectTracker();
      final comb = objectAt('comb', spokenAs: 'small object');
      final marker = objectAt('marker', spokenAs: 'small object');

      expect(tracker.update([comb]), isEmpty);
      expect(tracker.update([marker]), isEmpty);
      final confirmed = tracker.update([comb]);

      expect(confirmed, hasLength(1));
      expect(confirmed.single.label, 'small object');
    });
  });
}
