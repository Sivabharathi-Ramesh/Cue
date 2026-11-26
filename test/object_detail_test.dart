import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart'
    show CameraImageData, CameraImageFormat, CameraImagePlane;
import 'package:cue/core/audio_bus.dart';
import 'package:cue/live/frame_pipeline.dart';
import 'package:cue/live/scene_router.dart';
import 'package:cue/vision/frame_source.dart';
import 'package:cue/vision/object_detect_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

CameraFrame _frame({int contrast = 0}) {
  const size = 64;
  final bytes = Uint8List(size * size * 3 ~/ 2);
  bytes.fillRange(0, bytes.length, 128);
  if (contrast > 0) {
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        bytes[y * size + x] = (x ~/ 4 + y ~/ 4).isEven
            ? 128 - contrast
            : 128 + contrast;
      }
    }
  }
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
        planes: [CameraImagePlane(bytes: bytes, bytesPerRow: size)],
        height: size,
        width: size,
      ),
    ),
  );
}

const _charger = {
  'class': 'charger',
  'confidence': 0.91,
  'x1_norm': 0.2,
  'y1_norm': 0.24,
  'x2_norm': 0.8,
  'y2_norm': 0.76,
};

const _person = {
  'class': 'person',
  'confidence': 0.98,
  'x1_norm': 0.13,
  'y1_norm': 0.18,
  'x2_norm': 0.87,
  'y2_norm': 0.82,
};

Map<String, Object> _line(
  String text, {
  double left = 24,
  double score = 0.95,
}) {
  return {
    'text': text,
    'rect': {'left': left, 'top': 27.0, 'right': left + 12, 'bottom': 33.0},
    'recognizedLanguages': ['en'],
    'points': [],
    'confidence': score,
    'elements': [],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const detector = MethodChannel('yolo_single_image_channel');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const ocr = MethodChannel('google_mlkit_text_recognizer');
  const tts = MethodChannel('flutter_tts');
  final instances = <MethodChannel>{};
  late Directory directory;
  late FramePipeline pipeline;
  late List<String> spoken;
  late List<String> results;
  late List<Map<String, Object>> boxes;
  late Completer<void> ocrStarted;
  late bool hasVisibleText;
  Completer<void>? pendingOcr;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('cue-detail-');
    for (final path in [
      ObjectDetectService.modelPath,
      ObjectDetectService.everydayModelPath,
    ]) {
      final model = path.split('/').last;
      await File('${directory.path}/$model').create();
    }
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    messenger.setMockMethodCallHandler(detector, (call) async {
      final id = (call.arguments as Map)['instanceId'];
      final channel = MethodChannel('${detector.name}_$id');
      instances.add(channel);
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'predictSingleImage') return {'boxes': boxes};
        return true;
      });
      return null;
    });
  });

  tearDownAll(() async {
    for (final channel in instances) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    messenger.setMockMethodCallHandler(paths, null);
    messenger.setMockMethodCallHandler(detector, null);
    await directory.delete(recursive: true);
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    boxes = [_charger];
    spoken = [];
    results = [];
    hasVisibleText = true;
    ocrStarted = Completer<void>();
    pendingOcr = null;
    pipeline = FramePipeline(onResult: results.add);
    messenger.setMockMethodCallHandler(ocr, (call) async {
      if (!ocrStarted.isCompleted) ocrStarted.complete();
      await pendingOcr?.future;
      if (!hasVisibleText) return {'text': '', 'blocks': []};
      return {
        'text': '20W\nAB12\n999\nROOM 4',
        'blocks': [
          {
            'text': '20W\nAB12\n999\nROOM 4',
            'rect': {'left': 2.0, 'top': 27.0, 'right': 36.0, 'bottom': 33.0},
            'recognizedLanguages': ['en'],
            'points': [],
            'lines': [
              _line('ROOM 4', left: 2),
              _line('999', score: 0.48),
              _line('20W'),
              _line('20W'),
              _line('AB12'),
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

  Future<void> showFrame({
    int contrast = 0,
    Duration wait = const Duration(milliseconds: 350),
  }) async {
    pipeline.handleFrame(_frame(contrast: contrast));
    await Future<void>.delayed(wait);
  }

  test(
    'an item request keeps a pen drive overlapping a person detection',
    () async {
      boxes = [
        _person,
        {..._charger, 'class': 'pen drive'},
      ];
      pipeline.setInterpretation(Interpretation.object);
      expect(pipeline.requestManualRead(), isTrue);

      await showFrame();
      expect(results, isEmpty);
      await showFrame();

      expect(results.single.toLowerCase(), contains('pen drive'));
      expect(ocrStarted.isCompleted, isFalse);
      expect(spoken, results);
    },
  );

  test(
    'a person box prompts for an item and is spoken in a scene scan',
    () async {
      boxes = [_person];
      pipeline.setInterpretation(Interpretation.object);
      expect(pipeline.requestManualRead(), isTrue);
      for (var pass = 0; pass < 5; pass++) {
        await showFrame(contrast: 45);
      }
      expect(results.single, startsWith('I’m unsure what’s in view.'));
      expect(spoken, results);

      expect(pipeline.requestManualRead(wholeScene: true), isTrue);
      await showFrame(contrast: 45);
      await showFrame(contrast: 45);
      expect(results, hasLength(2));
      expect(results.last.toLowerCase(), contains('person'));
      expect(spoken, results);
    },
  );

  test('automatic descriptions confirm a steady low-contrast view', () async {
    pipeline.automaticDescriptions = true;
    pipeline.setInterpretation(Interpretation.object);

    const scanInterval = Duration(milliseconds: 710);
    await showFrame(contrast: 1, wait: scanInterval);
    await showFrame(contrast: 1, wait: scanInterval);
    expect(results, isEmpty);
    await showFrame(contrast: 1);

    expect(results.single.toLowerCase(), contains('charger'));
    expect(spoken, results);
  });

  test(
    'a close-up describes the item and reads only its clear markings',
    () async {
      expect(pipeline.requestObjectDetails(), isTrue);
      await showFrame();
      expect(ocrStarted.isCompleted, isFalse);
      await showFrame();

      expect(results.single.toLowerCase(), contains('charger'));
      expect(results.single, endsWith('The visible text reads, 20W, AB12.'));
      expect(spoken, results);
    },
  );

  test(
    'a close-up with no confident detection can still read visible text',
    () async {
      boxes = [];
      expect(pipeline.requestObjectDetails(), isTrue);
      for (var pass = 0; pass < 5; pass++) {
        await showFrame();
      }

      expect(results, ['The visible text reads, 20W, AB12.']);
      expect(spoken, results);
    },
  );

  test(
    'an unclear close-up speaks uncertainty once and gives a next step',
    () async {
      boxes = [];
      hasVisibleText = false;
      expect(pipeline.requestObjectDetails(), isTrue);
      for (var pass = 0; pass < 5; pass++) {
        await showFrame(contrast: 45);
      }

      expect(results.single, startsWith('I’m unsure what’s in view.'));
      expect(spoken, results);
    },
  );

  test('cancelling a close-up discards an in-flight reading', () async {
    pendingOcr = Completer<void>();
    expect(pipeline.requestObjectDetails(), isTrue);
    await showFrame();
    await showFrame();
    expect(ocrStarted.isCompleted, isTrue);
    pipeline.cancelRequestedScans();
    pendingOcr!.complete();
    await Future<void>.delayed(Duration.zero);

    expect(results, isEmpty);
    expect(spoken, isEmpty);
  });
}
