import 'dart:io';
import 'dart:typed_data';

import 'package:cue/core/finder_request.dart';
import 'package:cue/core/personal_items.dart';
import 'package:cue/core/search_target.dart';
import 'package:cue/live/item_search.dart';
import 'package:cue/vision/detected_object.dart';
import 'package:cue/vision/personal_item_vision.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

PersonalExample _example() => PersonalExample(
  format: 'test-model',
  foreground: [1, 0, 0],
  background: const [
    [0, 1, 0],
  ],
);

PersonalItem _profile(String name) =>
    PersonalItem(name, List.generate(3, (_) => _example()));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Find keeps the full item name and Teach accepts English and Hindi', () {
    final find = FinderRequest.parse(
      'Could you please find my blue phone case, please?',
    );
    expect(find?.action, FinderAction.find);
    expect(find?.name, 'blue phone case');
    expect(builtInFinderTarget(find!.name), isNull);
    expect(builtInFinderTarget('My ignition key'), SearchTarget.keys);
    expect(builtInFinderTarget('the TV remote'), SearchTarget.remote);
    expect(builtInFinderTarget('my phone charger'), SearchTarget.charger);
    expect(builtInFinderTarget('मेरी कंघी'), SearchTarget.comb);
    expect(
      FinderRequest.parse('Teach Cue my Travel Mug')?.action,
      FinderAction.teach,
    );
    expect(FinderRequest.parse('मेरी लाल चाबी खोजो')?.name, 'लाल चाबी');
    expect(FinderRequest.parse('लाल चाबी सीखो')?.action, FinderAction.teach);
    expect(FinderRequest.parse('read this page'), isNull);
  });

  test('a taught pen drive can be found by an unambiguous spoken alias', () {
    final penDrive = _profile('Pendrive');
    final usb = _profile('USB drive');
    expect(taughtFinderItem([penDrive], 'my pen drive'), same(penDrive));
    expect(taughtFinderItem([penDrive], 'USB stick'), same(penDrive));
    expect(taughtFinderItem([penDrive], 'पेन ड्राइव'), same(penDrive));
    expect(taughtFinderItem([penDrive, usb], 'USB drive'), same(usb));
    expect(taughtFinderItem([penDrive, usb], 'flash drive'), isNull);
    expect(taughtFinderItem([penDrive], 'pen'), isNull);
  });

  test(
    'an item can be saved, found by name, replaced and removed after restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cue-finder-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = PersonalItemStore(directory: () async => directory);
      expect(await store.read(), isEmpty);

      await Future.wait([
        store.save(_profile('My Travel Mug')),
        store.save(_profile('लाल चाबी')),
      ]);
      final restarted = PersonalItemStore(directory: () async => directory);
      final loaded = await restarted.read();
      final mug = taughtFinderItem(loaded, 'travel mug');
      expect(mug?.name, 'My Travel Mug');
      expect(mug?.examples.length, 3);
      expect(taughtFinderItem(loaded, 'मेरी लाल चाबी')?.name, 'लाल चाबी');
      await restarted.save(_profile('Travel mug'));
      expect((await restarted.read()).map((item) => item.name), [
        'Travel mug',
        'लाल चाबी',
      ]);

      await restarted.forget(mug!);
      expect((await restarted.read()).single.name, 'लाल चाबी');
      expect(
        await directory
            .list()
            .map((file) => file.path.split('/').last)
            .toList(),
        ['cue_personal_items.json'],
      );
    },
  );

  test(
    'a profile rejects its background, ambiguous matches and unrelated vectors',
    () {
      final item = _profile('Travel Mug');
      expect(item.score(unitEmbedding([1, 0.1, 0])), closeTo(1, 0.01));
      expect(item.score([0, 1, 0]), isNull);
      expect(item.score(unitEmbedding([0.72, 0.69, 0])), isNull);
      expect(item.score([0, 0, 1]), isNull);
      expect(
        () => PersonalItem('Travel Mug', [_example()]),
        throwsFormatException,
      );
    },
  );

  test('a taught match uses full-frame coordinates and waits for three fresh views', () {
    final start = DateTime(2026, 11, 20);
    final search = ItemSearch.personal(_profile('Blue Key'), start);
    const key = DetectedObject(
      name: 'Blue Key',
      confidence: 0.83,
      box: Rect.fromLTWH(0.65, 0.5, 0.30, 0.20),
    );
    search.beginFrame(start, 0);
    expect(search.observe([]).match, isNull);
    expect(search.scanDetail, isTrue);
    for (var frame = 1; frame <= 3; frame++) {
      search.beginFrame(start.add(Duration(milliseconds: frame * 500)), 0);
      final result = search.observe([key]);
      expect(search.region, isNull);
      expect(search.scanDetail, isTrue);
      expect(
        result.match?.direction,
        frame < 3 ? isNull : ObjectDirection.right,
      );
    }
    search.beginFrame(start.add(const Duration(seconds: 5)), 0);
    expect(search.observe([key]).match, isNull);
  });

  test('a borderline taught pen drive is checked at a tighter scale', () {
    final start = DateTime(2026, 11, 20);
    final search = ItemSearch.personal(_profile('Pen drive'), start);
    const drive = DetectedObject(
      name: 'Pen drive',
      confidence: 0.71,
      box: Rect.fromLTWH(0.53, 0.35, 0.40, 0.24),
    );
    for (var frame = 0; frame < 3; frame++) {
      search.beginFrame(start.add(Duration(milliseconds: frame * 500)), 0);
      expect(
        search.observe([drive], personalDirection: ObjectDirection.right).match,
        isNull,
      );
    }
    final crop = search.region!;
    expect(search.isVerifying, isTrue);
    expect(crop.width, lessThan(drive.box.width));
    expect(crop.center, drive.box.center);

    search.beginFrame(start.add(const Duration(milliseconds: 1500)), 0);
    final verified = search.observe([
      const DetectedObject(
        name: 'Pen drive',
        confidence: 0.73,
        box: Rect.fromLTWH(0, 0, 1, 1),
      ),
    ]);
    expect(verified.match?.box, crop);
    expect(verified.personalDirection, ObjectDirection.right);
  });

  test('a taught match stays tentative when the closer view is empty', () {
    final start = DateTime(2026, 11, 20);
    final search = ItemSearch.personal(_profile('Pen drive'), start);
    const drive = DetectedObject(
      name: 'Pen drive',
      confidence: 0.71,
      box: Rect.fromLTWH(0.3, 0.35, 0.40, 0.24),
    );
    for (var frame = 0; frame < 3; frame++) {
      search.beginFrame(start.add(Duration(milliseconds: frame * 500)), 0);
      expect(search.observe([drive]).match, isNull);
    }
    search.beginFrame(start.add(const Duration(milliseconds: 1500)), 0);
    expect(search.observe([]).match, isNull);
    expect(search.isVerifying, isFalse);
    expect(search.region, isNull);
    expect(search.scanDetail, isTrue);
  });

  test(
    'native feature windows support side guidance only when they agree',
    () async {
      const channel = MethodChannel('cue/personal_items');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var competingView = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'describe');
        final regions = call.arguments['regions'] as List;
        final vectors = <Float32List>[];
        for (final region in regions.cast<List>()) {
          final [double left, double top, double right, double bottom] = region;
          expect(left, inInclusiveRange(0, right));
          expect(top, inInclusiveRange(0, bottom));
          expect(right, lessThanOrEqualTo(1));
          expect(bottom, lessThanOrEqualTo(1));
          final width = right - left;
          final isRight = (left + right) / 2 > 0.64;
          final isLeft = (left + right) / 2 < 0.36;
          vectors.add(
            Float32List.fromList(
              regions.length > 3 &&
                      width < 0.6 &&
                      (isRight || (isLeft && competingView))
                  ? [1, 0, 0]
                  : [0, 1, 0],
            ),
          );
        }
        return {'format': 'test-model', 'vectors': vectors};
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      const vision = PersonalItemVision();
      final item = _profile('Blue Key');
      final jpeg = Uint8List.fromList([1]);
      final right = await vision.find(
        jpeg,
        const Size(480, 854),
        item,
        detail: false,
      );
      expect(right.direction, ObjectDirection.right);
      expect(right.candidates.single.name, item.name);

      competingView = true;
      final ambiguous = await vision.find(
        jpeg,
        const Size(480, 854),
        item,
        detail: true,
      );
      expect(ambiguous.direction, isNull);
      expect(ambiguous.candidates, hasLength(1));
      await expectLater(
        vision.capture(jpeg, const Size(480, 854)),
        throwsA(isA<UnclearPersonalExample>()),
      );
    },
  );

  test(
    'taught-item verification scores only the newly cropped image',
    () async {
      const channel = MethodChannel('cue/personal_items');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var resemblesItem = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'describe');
        expect(call.arguments['regions'], [
          [0.0, 0.0, 1.0, 1.0],
        ]);
        return {
          'format': 'test-model',
          'vectors': [
            resemblesItem ? [1, 0, 0] : [0, 1, 0],
          ],
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      const vision = PersonalItemVision();
      final jpeg = Uint8List.fromList([1]);
      final item = _profile('Pen drive');
      Future<({List<DetectedObject> candidates, ObjectDirection? direction})>
      verify() => vision.find(
        jpeg,
        const Size(480, 854),
        item,
        detail: false,
        verifyCrop: true,
      );

      final seen = await verify();
      expect(seen.candidates.single.box, const Rect.fromLTWH(0, 0, 1, 1));
      expect(seen.direction, isNull);
      resemblesItem = false;
      expect((await verify()).candidates, isEmpty);
    },
  );
}
