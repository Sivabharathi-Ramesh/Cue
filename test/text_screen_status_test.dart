import 'dart:async';

import 'package:camera/camera.dart';
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart'
    show CameraImageData, CameraImageFormat, CameraImagePlane;
import 'package:cue/core/audio_bus.dart';
import 'package:cue/live/frame_pipeline.dart';
import 'package:cue/live/scene_router.dart';
import 'package:cue/vision/frame_source.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

CameraFrame _frame({required bool brighter, bool dark = false}) {
  const side = 64;
  final bytes = Uint8List(side * side * 3 ~/ 2);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final tone = (x ~/ 4 + y ~/ 4).isEven ? 90 : 180;
      bytes[y * side + x] = dark ? tone ~/ 8 : tone + (brighter ? 28 : 0);
    }
  }
  bytes.fillRange(side * side, bytes.length, 128);
  return CameraFrame(
    description: const CameraDescription(
      name: 'test camera',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 0,
    ),
    deviceOrientation: DeviceOrientation.portraitUp,
    image: CameraImage.fromPlatformInterface(
      CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.nv21, raw: 17),
        planes: [CameraImagePlane(bytes: bytes, bytesPerRow: side)],
        height: side,
        width: side,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ocr = MethodChannel('google_mlkit_text_recognizer');
  const tts = MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late String textInView;
  late double confidence;
  late bool brighter;
  late List<String> spoken;
  late List<String> results;
  late FramePipeline pipeline;
  Completer<void>? pendingOcr;
  TextRecognitionScript? visibleScript;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    textInView = '';
    confidence = 0.95;
    brighter = false;
    spoken = <String>[];
    results = <String>[];
    pipeline = FramePipeline(onResult: results.add);
    pendingOcr = null;
    visibleScript = null;
    messenger.setMockMethodCallHandler(ocr, (call) async {
      await pendingOcr?.future;
      final script = (call.arguments as Map<Object?, Object?>)['script'];
      if (visibleScript != null && script != visibleScript!.index) {
        return {'text': '', 'blocks': []};
      }
      const rect = {'left': 8.0, 'top': 12.0, 'right': 57.0, 'bottom': 41.0};
      return {
        'text': textInView,
        'blocks': [
          if (textInView.isNotEmpty)
            {
              'text': textInView,
              'rect': rect,
              'recognizedLanguages': ['en'],
              'points': [],
              'lines': [
                for (final line in textInView.split('\n'))
                  {
                    'text': line,
                    'rect': rect,
                    'recognizedLanguages': ['en'],
                    'points': [],
                    'confidence': confidence,
                    'elements': [],
                  },
              ],
            },
        ],
      };
    });
    messenger.setMockMethodCallHandler(tts, (call) async {
      if (call.method == 'isLanguageAvailable') return true;
      if (call.method == 'getVoices') return [];
      if (call.method == 'speak') {
        final argument = call.arguments;
        spoken.add((argument is Map ? argument['text'] : argument) as String);
      }
      return 1;
    });
  });

  tearDown(() async {
    pipeline.reset();
    if (pendingOcr case final pending? when !pending.isCompleted) {
      pending.complete();
    }
    await AudioBus.instance.stop();
    AudioBus.instance.forgetLastResult();
    messenger.setMockMethodCallHandler(ocr, null);
    messenger.setMockMethodCallHandler(tts, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> show(String text, {bool dark = false}) async {
    textInView = text;
    brighter = !brighter;
    pipeline.handleFrame(_frame(brighter: brighter, dark: dark));
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  test('live Text mode reads screen changes and recovers from an empty first frame', () async {
    expect(pipeline.interpretation, Interpretation.text);
    await show('Loading…');
    expect(results, isEmpty);
    await show('Loading…');
    await show('Loading…');
    expect(results, ['Loading.']);

    await show('Working on updates\n42% complete');
    await show('Working on updates\n42% complete');
    expect(results, ['Loading.', 'Updating, 42 percent.']);
    expect(spoken, containsAllInOrder(results));

    const page = 'The garden is open every morning.';
    expect(pipeline.requestManualRead(), isTrue);
    await show('');
    expect(pipeline.isCheckingForText, isTrue);
    expect(spoken, ['Loading.', 'Updating, 42 percent.']);
    await show(page);
    expect(results.last, page);
    expect(spoken, contains(page));
    expect(pipeline.isCheckingForText, isFalse);
    expect(pipeline.interpretation, Interpretation.text);

    pipeline.startScreenWatch();
    expect(pipeline.isWatchingScreen, isTrue);
    expect(pipeline.interpretation, Interpretation.text);
    await show('Press Enter to continue');
    expect(results.last, page);
    await show('Press Enter to continue');
    expect(results.last, 'The screen says, Press Enter to continue.');
    expect(spoken, contains(results.last));
    expect(pipeline.stopScreenWatch(), isTrue);
    expect(pipeline.isWatchingScreen, isFalse);
  });

  test(
    'a blank view stays quiet and a requested check gives one hint',
    () async {
      await show('');
      await show('');
      await show('');
      expect(results, isEmpty);
      expect(spoken, isEmpty);

      expect(pipeline.requestManualRead(), isTrue);
      pendingOcr = Completer<void>();
      await show('', dark: true);
      expect(pipeline.requestManualRead(), isFalse);
      expect(spoken, isEmpty);

      await Future<void>.delayed(const Duration(seconds: 3));
      expect(pipeline.isCheckingForText, isFalse);
      const hint = 'Try adding more light to the text.';
      expect(results, [hint]);
      expect(spoken, [hint]);

      textInView = 'This reading finished after the check ended.';
      pendingOcr!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(results, [hint]);
      expect(spoken, [hint]);
    },
  );

  test('a requested check confirms uncertain text before reading it', () async {
    confidence = 0.66;
    const text = 'The garden is open every morning.';
    expect(pipeline.requestManualRead(), isTrue);
    await show(text);
    expect(results, isEmpty);
    expect(spoken, isEmpty);
    await show(text);
    expect(results, ['Maybe: $text']);
    expect(pipeline.isCheckingForText, isFalse);
  });

  test('a requested check keeps using the script that found text', () async {
    visibleScript = TextRecognitionScript.devanagiri;
    confidence = 0.66;
    const text = 'कृपया दरवाजा खोलें।';
    expect(pipeline.requestManualRead(), isTrue);
    await show(text);
    expect(results, isEmpty);
    await show(text);
    expect(results, ['शायद: $text']);
    expect(pipeline.isCheckingForText, isFalse);
  });
}
