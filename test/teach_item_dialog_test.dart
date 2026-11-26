import 'dart:async';

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
    'guided capture resumes after rejected photos and a spoken name starts search',
    (tester) async {
      final controller = _PreviewController();
      final camera = ValueNotifier<CameraController?>(controller);
      final volumeShortcut = ValueNotifier(0);
      addTearDown(controller.dispose);
      addTearDown(camera.dispose);
      addTearDown(volumeShortcut.dispose);
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
                        sayName: () async => 'Pendrive',
                        capture: () async {
                          attempts++;
                          if (attempts == 1) {
                            throw const UnclearPersonalExample(tooDark: true);
                          }
                          return PersonalExample(
                            format: 'test-model',
                            foreground: switch (attempts) {
                              3 || 4 => [0, 0, 1],
                              _ => [1, 0, 0],
                            },
                            background: const [
                              [0, 1, 0],
                            ],
                          );
                        },
                        save: (item) async => items.add(item),
                        announce: (message) async => spoken.add(message),
                        volumeShortcut: volumeShortcut,
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
                          sayName: () async => 'Find my USB stick',
                          removeItem: (item) async => items.remove(item),
                          announce: spoken.add,
                          volumeShortcut: volumeShortcut,
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
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await tap('Open Teach');
      volumeShortcut.value++;
      await tester.pumpAndSettle();
      expect(find.text('Teach Pendrive'), findsOneWidget);
      expect(find.byType(CameraPreview), findsOneWidget);
      expect(attempts, 0);
      await tap(strings.startCapture);
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        spoken.last,
        '${strings.itemCaptureDark} ${strings.teachingAutoRetry}',
      );
      expect(find.text('0 of 3 photos'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 600));
      expect(spoken.last, startsWith('One of three photos accepted.'));
      expect(find.text('1 of 3 photos'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        spoken.last,
        '${strings.itemCaptureDifferent} ${strings.teachingAutoRetry}',
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 600));
      expect(spoken.last, endsWith('When ready, hold volume down to retry.'));
      expect(find.text(strings.retryCapture), findsOneWidget);
      expect(find.text('1 of 3 photos'), findsOneWidget);

      await tap(strings.retryCapture);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(items.single.name, 'Pendrive');
      expect(items.single.examples.length, 3);
      expect(attempts, 6);
      expect(spoken, contains(strings.teachingPrompt(2)));

      await tap('Open Find');
      expect(find.text('Keys'), findsOneWidget);
      expect(find.text('Remote control'), findsNothing);
      await tap(strings.moreCommonItems);
      expect(find.text('Remote control'), findsOneWidget);
      await tap(strings.moreCommonItems);
      expect(find.byType(TextField), findsNothing);
      await tap(strings.typeItemName);
      await tester.enterText(find.byType(TextField), 'Sunglass case');
      await tap(strings.startSearch);
      expect(find.text(strings.unrecognizedItem), findsOneWidget);
      expect(find.text('Teach Sunglass case'), findsOneWidget);
      await tap(strings.sayWhatToFind);
      expect(request?.name, 'usb stick');
      expect(request?.action, FinderAction.find);
      expect(find.text(strings.findItem), findsNothing);
    },
  );

  testWidgets(
    'named teaching waits for spoken guidance and cancels before another photo',
    (tester) async {
      final camera = ValueNotifier<CameraController?>(null);
      addTearDown(camera.dispose);
      final holdPrompt = Completer<void>();
      var captures = 0;
      var saves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<PersonalItem>(
                  context: context,
                  builder: (context) => TeachItemDialog(
                    strings: strings,
                    camera: camera,
                    items: const [],
                    initialName: 'Blue wallet',
                    sayName: () async => null,
                    capture: () async {
                      captures++;
                      return PersonalExample(
                        format: 'test-model',
                        foreground: [1, 0, 0],
                        background: const [
                          [0, 1, 0],
                        ],
                      );
                    },
                    save: (_) async => saves++,
                    announce: (message) async {
                      if (message == strings.teachingPrompt(0)) {
                        await holdPrompt.future;
                      }
                    },
                  ),
                ),
                child: const Text('Open Teach'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Teach'));
      await tester.pumpAndSettle();
      expect(find.text('Teach Blue wallet'), findsOneWidget);
      expect(find.text(strings.sayItemName), findsNothing);
      await tester.tap(find.text(strings.startCapture));
      await tester.pump(const Duration(seconds: 5));
      expect(captures, 0);

      holdPrompt.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(captures, 1);
      await tester.tap(find.text(strings.cancel));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));
      expect(captures, 1);
      expect(saves, 0);
    },
  );
}
