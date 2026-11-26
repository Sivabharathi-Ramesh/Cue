import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import 'detected_object.dart';
import '../core/search_target.dart';
import 'object_colour.dart';

/// On-device object detection.
///
/// The model is a YOLOE-26s detector exported for Cue's everyday vocabulary.
/// It never leaves the phone, matching Cue's privacy promise. It recognises a
/// curated set of common household/everyday classes; it cannot name things
/// outside that set.
class ObjectDetectService {
  ObjectDetectService._(this._asset);

  static final ObjectDetectService instance = ObjectDetectService._(modelPath);

  /// A new filename lets the plugin refresh the model on existing installs.
  static const String modelPath =
      'assets/models/yoloe26s_household_v5_w8a32.tflite';

  // The native plugin keeps the highest-scoring class at each position.
  // Use the calibrated everyday model for automatic speech and established
  // Finder targets so the expanded vocabulary does not compete with them.
  static const String everydayModelPath =
      'assets/models/yoloe26s_everyday_v4_w8a32.tflite';
  static final ObjectDetectService everyday = ObjectDetectService._(
    everydayModelPath,
  );

  final String _asset;

  /// Admit small boxes that meet the scene confidence threshold.
  static const double _minArea = 0.002;

  /// A detection that fills nearly the whole frame is usually a wall, a hand
  /// or a reflection, not the object the user is pointing at.
  static const double _maxArea = 0.94;

  YOLO? _yolo;
  Future<void>? _loading;
  bool _usingGpu = true;

  /// Loads the model before the object mode is needed.
  Future<void> warmUp() async {
    try {
      await _ensureLoaded();
    } catch (error) {
      if (kDebugMode) debugPrint('Object model warm-up failed: $error');
    }
  }

  Future<void> _ensureLoaded() async {
    if (_yolo != null) return;
    final pending = _loading ??= _load();
    try {
      await pending;
    } finally {
      if (identical(_loading, pending)) _loading = null;
    }
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
      modelPath: _asset,
      task: YOLOTask.detect,
      // A blind user needs the latency before they finish waiting.
      useGpu: useGpu,
      // Keep the replacement CPU instance independent of the GPU instance.
      useMultiInstance: true,
    );
    try {
      if (!await yolo.loadModel()) {
        throw StateError('Could not load the object detector');
      }
    } catch (_) {
      await yolo.dispose();
      rethrow;
    }
    if (kDebugMode) debugPrint('live: model loaded gpu=$useGpu');
    return yolo;
  }

  /// Detects objects in one JPEG image.
  ///
  /// Returns objects or throws if inference is unavailable.
  Future<List<DetectedObject>> detect(
    Uint8List jpeg, {
    int maxObjects = 3,
    bool includeCandidates = false,
    bool includePeople = true,
    SearchTarget? searchTarget,
  }) async {
    if (jpeg.length < 32) return const <DetectedObject>[];
    await _ensureLoaded();
    final raw = await _predict(
      jpeg,
      // Keep rival labels available for the ambiguity check below.
      confidenceThreshold: switch (searchTarget) {
        null => 0.40,
        SearchTarget.keys => searchCandidateConfidence(SearchTarget.keys),
        _ => 0.34,
      },
      // Keep overlapping scene candidates long enough to compare competing
      // labels in Dart. Android suppresses boxes across all classes here.
      iouThreshold: switch (searchTarget) {
        null => 0.75,
        SearchTarget.keys => 0.88,
        _ => 0.45,
      },
    );
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
        .where(
          (object) =>
              object.name.isNotEmpty &&
              object.confidence.isFinite &&
              object.confidence >= 0 &&
              object.confidence <= 1 &&
              object.box.isFinite &&
              !object.box.isEmpty,
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

    if (searchTarget != null) {
      // Inspect every candidate before general scene ranking and size filters.
      final rivals = rawObjects.where(
        (item) => !searchTarget.labels.contains(item.name),
      );
      return rawObjects
          .where(
            (item) =>
                isSearchCandidate(item, searchTarget) &&
                !resolveObjectAmbiguity(item, rivals).isAmbiguous,
          )
          .toList();
    }

    final chosen = selectSceneObjects(
      rawObjects,
      includeCandidates: includeCandidates,
      includePeople: includePeople,
      limit: maxObjects,
    );
    return _withColours(chosen, jpeg);
  }

  @visibleForTesting
  static List<DetectedObject> selectSceneObjects(
    List<DetectedObject> rawObjects, {
    required int limit,
    bool includeCandidates = false,
    bool includePeople = true,
  }) {
    // In a close-up, a hand can produce a person box over the held item.
    // Leave that box out before it can displace the item during deduplication.
    final objects =
        rawObjects
            .where(
              (object) =>
                  (includePeople || object.name != 'person') &&
                  _plausible(object),
            )
            .toList()
          ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final resolved = objects
        .map((object) => resolveObjectAmbiguity(object, objects))
        .toList();
    // Use weaker predictions as evidence of ambiguity, but let the candidates
    // eligible for speech claim their boxes first.
    final candidates = [
      ...resolved.where(isConfidentDetection),
      if (includeCandidates)
        ...resolved.where((object) => !isConfidentDetection(object)),
    ];
    final unique = <DetectedObject>[];
    for (final object in candidates) {
      if (unique.any((kept) => boxIou(kept.box, object.box) >= 0.55)) continue;
      unique.add(object);
    }
    unique.sort((a, b) => _relevance(b).compareTo(_relevance(a)));
    return unique.take(limit).toList(growable: false);
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

  /// Runs inference, retreating to the CPU once if the GPU delegate accepts
  /// the model at load time but fails on the first real image.
  Future<Map<String, dynamic>> _predict(
    Uint8List jpeg, {
    required double confidenceThreshold,
    required double iouThreshold,
  }) async {
    final yolo = _yolo!;
    try {
      return await yolo.predict(
        jpeg,
        confidenceThreshold: confidenceThreshold,
        iouThreshold: iouThreshold,
      );
    } catch (_) {
      if (!_usingGpu) rethrow;
      _yolo = await _create(useGpu: false);
      _usingGpu = false;
      await yolo.dispose();
      return _yolo!.predict(
        jpeg,
        confidenceThreshold: confidenceThreshold,
        iouThreshold: iouThreshold,
      );
    }
  }

  // The upright shape is useful for estimating distance, but the same bottle
  // or toothbrush can be recognised lying flat.
  static bool _plausible(DetectedObject object) =>
      object.area >= _minArea &&
      object.area <= _maxArea &&
      hasPlausibleLargeClassArea(object);

  static double _relevance(DetectedObject object) {
    final centre = (object.box.center.dx - 0.5).abs() * 2; // 0 centre, 1 edge
    final centred = 1.0 - centre;
    final size = object.area.clamp(0.0, 1.0);
    return object.confidence + 0.12 * centred + 0.06 * size;
  }
}
