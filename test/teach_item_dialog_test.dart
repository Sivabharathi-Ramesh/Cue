import 'package:camera/camera.dart';
import 'package:cue/core/cue_language.dart';
import 'package:cue/core/cue_strings.dart';
import 'package:cue/core/finder_request.dart';
import 'package:cue/core/personal_items.dart';
import 'package:cue/live/finder_dialog.dart';
import 'package:cue/live/teach_item_dialog.dart';
import 'package:cue/vision/personal_item_vision.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PreviewController extends CameraController {
  _PreviewController()
    : super(
        const CameraDescription(
          name: 'test-camera',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
        ),
        ResolutionPreset.medium,
      ) {
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(640, 480),
    );
  }

  @override
  Widget buildPreview() => const ColoredBox(color: Colors.black);
}

void main() {
  const strings = CueStrings(CueLanguage.english);

  testWidgets(
    'teach retries an unclear view, saves three examples and makes it findable',
    (tester) async {
      final controller = _PreviewController();
      final camera = ValueNotifier<CameraController?>(controller);
      addTearDown(controller.dispose);
      addTearDown(camera.dispose);
      final items = <PersonalItem>[];
      final spoken = <String>[];
      FinderRequest? request;
      var attempts = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () => showDialog<PersonalItem>(
                      context: context,
                      builder: (context) => TeachItemDialog(
                        strings: strings,
                        camera: camera,
                        items: items,
                        sayName: () async => 'Blue wallet',
                        capture: () async {
                          attempts++;
                          if (attempts == 1) {
                            throw const UnclearPersonalExample();
                          }
                          return PersonalExample(
                            format: 'test-model',
                            foreground: attempts == 3 ? [0, 0, 1] : [1, 0, 0],
                            background: const [
                              [0, 1, 0],
                            ],
                          );
                        },
                        save: (item) async => items.add(item),
                        announce: spoken.add,
                      ),
                    ),
                    child: const Text('Open Teach'),
                  ),
                  TextButton(
                    onPressed: () async {
                      request = await showDialog<FinderRequest>(
                        context: context,
                        builder: (context) => FinderDialog(
                          strings: strings,
                          items: items,
                          sayName: () async => 'Find my blue wallet',
                          removeItem: (item) async => items.remove(item),
                          announce: spoken.add,
                        ),
                      );
                    },
                    child: const Text('Open Find'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      Future<void> tap(String label) async {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await tap('Open Teach');
      await tap(strings.sayItemName);
      await tap(strings.next);
      expect(find.text('Teach Blue wallet'), findsOneWidget);
      expect(find.byType(CameraPreview), findsOneWidget);
      await tap(strings.captureExample);
      expect(find.text(strings.itemCaptureUnclear), findsOneWidget);
      expect(find.text('0 of 3 examples'), findsOneWidget);
      await tap(strings.captureExample);
      await tap(strings.captureExample);
      expect(find.text(strings.itemCaptureDifferent), findsOneWidget);
      expect(find.text('1 of 3 examples'), findsOneWidget);
      await tap(strings.captureExample);
      await tap(strings.captureExample);
      expect(find.text('3 of 3 examples'), findsOneWidget);
      await tap(strings.saveItem);
      expect(items.single.name, 'Blue wallet');
      expect(items.single.examples.length, 3);
      expect(spoken, contains(strings.teachingPrompt(2)));

      await tap('Open Find');
      await tester.enterText(find.byType(TextField), 'Sunglass case');
      await tap(strings.startSearch);
      expect(find.text(strings.unrecognizedItem), findsOneWidget);
      await tap(strings.sayItemName);
      await tap(strings.startSearch);
      expect(request?.name, 'blue wallet');
      expect(request?.action, FinderAction.find);
    },
  );
}
