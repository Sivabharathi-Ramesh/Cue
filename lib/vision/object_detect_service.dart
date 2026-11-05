import 'dart:async';
import 'dart:typed_data';

import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// On-device object detection.
///
/// The model is the nano YOLO 26 detector, bundled in assets. It never
/// leaves the phone, matching Cue's privacy promise. It recognises the 80
/// COCO classes; it cannot name things it was never shown.
class ObjectDetectService {
  ObjectDetectService._();

  static final ObjectDetectService instance = ObjectDetectService._();

  /// Bundled model path.
  static const String modelPath = 'assets/models/yolo26n_w8a32.tflite';

  YOLO? _yolo;
  Future<void>? _loading;

  /// Loads the model before the object mode is needed.
  Future<void> warmUp() => _ensureLoaded().then((_) {});

  Future<void> _ensureLoaded() {
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final yolo = YOLO(
      modelPath: modelPath,
      task: YOLOTask.detect,
      // A blind user needs the latency before they finish waiting. CPU is
      // acceptable on this hardware; the plugin falls back automatically.
      useGpu: true,
    );
    await yolo.loadModel();
    _yolo = yolo;
  }

  /// Detects objects in one JPEG image.
  ///
  /// Returns class names, most confident first, with repeats removed. The
  /// list is limited to [maxObjects]; more than three objects is noise for
  /// someone listening, not help.
  Future<List<String>> detect(
    Uint8List jpeg, {
    double confidence = 0.45,
    int maxObjects = 3,
  }) async {
    if (jpeg.length < 32) return const <String>[];
    await _ensureLoaded();

    try {
      final raw = await _yolo!.predict(
        jpeg,
        confidenceThreshold: confidence,
        iouThreshold: 0.45,
      );
      final detections = (raw['detections'] as List<dynamic>? ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map(YOLOResult.fromMap)
          .toList();

      detections.sort((a, b) => b.confidence.compareTo(a.confidence));

      final seen = <String>{};
      final names = <String>[];
      for (final detection in detections) {
        final name = detection.className.toLowerCase().trim();
        if (name.isEmpty || seen.contains(name)) continue;
        seen.add(name);
        names.add(name);
        if (names.length >= maxObjects) break;
      }
      return names;
    } catch (_) {
      // A failed detection is not a reason to disrupt the session; the next
      // pass gets another chance.
      return const <String>[];
    }
  }
}
