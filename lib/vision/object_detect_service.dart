import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import 'detected_object.dart';
import 'object_colour.dart';

/// On-device object detection.
///
/// The model is a YOLOE-26s detector exported for Cue's everyday vocabulary.
/// It never leaves the phone, matching Cue's privacy promise. It recognises a
/// curated set of common household/everyday classes; it cannot name things
/// outside that set.
class ObjectDetectService {
  ObjectDetectService._();

  static final ObjectDetectService instance = ObjectDetectService._();

  /// Bundled model path.
  static const String modelPath =
      'assets/models/yoloe26s_everyday_w8a32.tflite';

  /// Below this, a box is almost always background clutter.
  static const double _minArea = 0.008;

  /// A detection that fills nearly the whole frame is usually a wall, a hand
  /// or a reflection, not the object the user is pointing at.
  static const double _maxArea = 0.94;

  YOLO? _yolo;
  Future<void>? _loading;
  bool _usingGpu = true;

  /// Loads the model before the object mode is needed.
  Future<void> warmUp() => _ensureLoaded().then((_) {});

  Future<void> _ensureLoaded() {
    return _loading ??= _load();
  }

  Future<void> _load() async {
    // Quantised models do not always run on the GPU delegate. Try it, and fall
    // back to the CPU rather than leaving object mode silently blind.
    try {
      _yolo = await _create(useGpu: true);
      _usingGpu = true;
    } catch (_) {
      _yolo = await _create(useGpu: false);
      _usingGpu = false;
    }
  }

  Future<YOLO> _create({required bool useGpu}) async {
    final yolo = YOLO(
      modelPath: modelPath,
      task: YOLOTask.detect,
      // A blind user needs the latency before they finish waiting.
      useGpu: useGpu,
    );
    await yolo.loadModel();
    if (kDebugMode) debugPrint('live: model loaded gpu=$useGpu');
    return yolo;
  }

  /// Detects objects in one JPEG image.
  ///
  /// Returns objects most relevant first, with duplicate labels removed.
  ///
  /// Three rules keep the output honest, because a confident-sounding wrong
  /// answer is worse than silence for a blind user:
  ///
  ///  * a high-confidence object is spoken on its own;
  ///  * lower-confidence objects are only spoken when at least two different
  ///    ordinary classes agree that *something* is there;
  ///  * boxes that are too small, too large, or the wrong shape for the class
  ///    are thrown away before anything is said.
  Future<List<DetectedObject>> detect(
    Uint8List jpeg, {
    int maxObjects = 3,
    bool lenient = false,
  }) async {
    if (jpeg.length < 32) return const <DetectedObject>[];
    await _ensureLoaded();

    try {
      final raw = await _predict(jpeg);
      if (kDebugMode) {
        debugPrint(
          'live: plugin accel=${raw['accelerator']} '
          'pre=${raw['preMs']} infer=${raw['inferenceMs']} '
          'post=${raw['postMs']}',
        );
      }

      final rawObjects = (raw['detections'] as List<dynamic>? ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map(YOLOResult.fromMap)
          .map(
            (result) => DetectedObject(
              name: result.className.toLowerCase().trim(),
              confidence: result.confidence,
              box: result.normalizedBox,
            ),
          )
          .toList();
      if (kDebugMode && rawObjects.isNotEmpty) {
        final top = [...rawObjects]
          ..sort((a, b) => b.confidence.compareTo(a.confidence));
        debugPrint(
          'live: raw ${rawObjects.length} '
          '${top.take(8).map((o) => '${o.name} ${(o.confidence * 100).round()}').join(', ')}',
        );
      }

      final objects = rawObjects.where(_plausible).toList();

      if (objects.isEmpty) return const <DetectedObject>[];

      objects.sort((a, b) => b.confidence.compareTo(a.confidence));

      // Two classes can land on the same box with almost the same score. For
      // fine-grained classes that is a near-tie, not an answer: comb vs knife,
      // marker vs pen. Replace the name with a safe group label before the
      // rest of the pipeline sees it.
      final resolved = <DetectedObject>[
        for (final object in objects) resolveObjectAmbiguity(object, objects),
      ];

      // Two classes on the same box ("cup" and "bottle" on one dinner table)
      // are one thing, not two. Keep the more confident label.
      final unique = <DetectedObject>[];
      for (final object in resolved) {
        final duplicate = unique.any(
          (kept) => _iou(kept.box, object.box) >= 0.55,
        );
        if (!duplicate) unique.add(object);
      }

      final strong = unique
          .where((object) => _isStrong(object, lenient))
          .toList();
      // The fallback exists so two ordinary classes can agree that *something*
      // is there when neither is strong. A strict or risky label is exactly
      // the kind that must not borrow confidence from a neighbour, so it is
      // not allowed into that pool.
      final moderate = unique
          .where(
            (object) =>
                !strictObjectClasses.contains(object.name) &&
                !riskyObjectClasses.contains(object.name) &&
                object.confidence >= (lenient ? 0.40 : 0.45),
          )
          .toList();

      // A pooled answer (side question or developer overlay) returns more of
      // the raw detections. A scene answer stays on the same honesty bar as
      // live narration: more names are useful, weak names are not.
      final chosen = maxObjects > 5
          ? unique.where((o) => o.confidence >= 0.30).toList()
          : (strong.isNotEmpty
                ? strong
                : (moderate.length >= 2 ? moderate : const <DetectedObject>[]));

      if (chosen.isEmpty) return const <DetectedObject>[];

      // Nearest and most central first: that is what the user is walking
      // towards, not whatever happened to score highest in a corner.
      chosen.sort((a, b) => _relevance(b).compareTo(_relevance(a)));
      final nearest = chosen.take(maxObjects).toList(growable: false);
      return await _withColours(nearest, jpeg);
    } catch (_) {
      // A failed detection is not a reason to disrupt the session; the next
      // pass gets another chance.
      return const <DetectedObject>[];
    }
  }

  /// Attaches the colour sampled from each box.
  ///
  /// The JPEG is decoded once for all boxes. Colour is an extra, never a
  /// precondition: a decode failure returns the objects exactly as they were.
  Future<List<DetectedObject>> _withColours(
    List<DetectedObject> objects,
    Uint8List jpeg,
  ) async {
    if (objects.isEmpty) return objects;

    ui.Image? image;
    try {
      final codec = await ui.instantiateImageCodec(jpeg);
      final frame = await codec.getNextFrame();
      image = frame.image;
      final width = image.width;
      final height = image.height;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return objects;
      final rgba = data.buffer.asUint8List();

      return <DetectedObject>[
        for (final object in objects)
          object.withColour(
            dominantColourInBox(rgba, width, height, object.box),
          ),
      ];
    } catch (_) {
      return objects;
    } finally {
      image?.dispose();
    }
  }

  /// Whether a detection is strong enough to speak on its own.
  bool _isStrong(DetectedObject object, bool lenient) {
    return isConfidentDetection(object, lenient: lenient);
  }

  /// Runs inference, retreating to the CPU once if the GPU delegate accepts
  /// the model at load time but fails on the first real image.
  Future<Map<String, dynamic>> _predict(Uint8List jpeg) async {
    try {
      return await _yolo!.predict(
        jpeg,
        confidenceThreshold: 0.40,
        iouThreshold: 0.45,
      );
    } catch (_) {
      if (!_usingGpu) rethrow;
      _yolo = await _create(useGpu: false);
      _usingGpu = false;
      return _yolo!.predict(
        jpeg,
        confidenceThreshold: 0.40,
        iouThreshold: 0.45,
      );
    }
  }

  bool _plausible(DetectedObject object) {
    if (object.name.isEmpty) return false;
    if (!hasPlausibleLargeClassArea(object)) return false;
    final area = object.area;
    if (area < _minArea || area > _maxArea) return false;
    if (object.isTallClass && !object.hasTallShape) return false;
    return true;
  }

  double _relevance(DetectedObject object) {
    final centre = (object.box.center.dx - 0.5).abs() * 2; // 0 centre, 1 edge
    final centred = 1.0 - centre;
    final size = object.area.clamp(0.0, 1.0);
    return object.confidence + 0.12 * centred + 0.06 * size;
  }

  double _iou(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.width <= 0 || intersection.height <= 0) return 0;
    final intersectionArea = intersection.width * intersection.height;
    final union = a.width * a.height + b.width * b.height - intersectionArea;
    return union <= 0 ? 0 : intersectionArea / union;
  }
}
