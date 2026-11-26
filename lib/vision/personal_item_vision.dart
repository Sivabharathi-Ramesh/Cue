import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../core/personal_items.dart';
import 'detected_object.dart';

class UnclearPersonalExample implements Exception {
  const UnclearPersonalExample({this.tooDark = false});

  final bool tooDark;
}

/// Uses the native feature extractor to learn and locate a named item.
class PersonalItemVision {
  const PersonalItemVision();

  static const _channel = MethodChannel('cue/personal_items');
  static const guideFraction = 0.76;

  Future<PersonalExample> capture(Uint8List jpeg, Size frame) async {
    final subject = _square(frame, guideFraction, 0.5, 0.5);
    final backgroundA = _square(frame, 0.24, 0, 0);
    final backgroundB = _square(frame, 0.24, 1, 1);
    final features = await _describe(jpeg, [subject, backgroundA, backgroundB]);
    final item = features.vectors.first;
    final background = features.vectors.skip(1);
    if (background.every(
      (vector) => embeddingSimilarity(item, vector) > 0.95,
    )) {
      throw const UnclearPersonalExample();
    }
    return PersonalExample(
      format: features.format,
      foreground: item,
      background: background,
    );
  }

  /// With [verifyCrop], score the tighter image already cut from the camera.
  Future<({List<DetectedObject> candidates, ObjectDirection? direction})> find(
    Uint8List jpeg,
    Size frame,
    PersonalItem item, {
    required bool detail,
    bool verifyCrop = false,
  }) async {
    final regions = verifyCrop
        ? const [Rect.fromLTWH(0, 0, 1, 1)]
        : searchRegions(frame, detail: detail);
    final features = await _describe(jpeg, regions);
    if (features.format != item.format) {
      throw const FormatException('The item needs an updated visual profile');
    }
    DetectedObject? best;
    final scoresByDirection = <ObjectDirection, double>{};
    for (var i = 0; i < regions.length; i++) {
      final score = item.score(features.vectors[i]);
      if (score == null) continue;
      final candidate = DetectedObject(
        name: item.name,
        confidence: score,
        box: regions[i],
      );
      final direction = candidate.direction;
      scoresByDirection[direction] = math.max(
        scoresByDirection[direction] ?? 0,
        score,
      );
      if (best == null || score > best.confidence) best = candidate;
    }
    final winner = best;
    if (winner == null) {
      return (candidates: const <DetectedObject>[], direction: null);
    }
    // A wide view may match even when its item is far from the crop's centre.
    // Give a side only when a tighter view beats the competing regions.
    final direction = winner.direction;
    final canGiveSide =
        direction != ObjectDirection.ahead &&
        winner.box.width <= 0.62 &&
        winner.confidence >= 0.70 &&
        scoresByDirection.entries.every(
          (entry) =>
              entry.key == direction || winner.confidence - entry.value >= 0.02,
        );
    return (candidates: [winner], direction: canGiveSide ? direction : null);
  }

  static List<Rect> searchRegions(Size frame, {required bool detail}) {
    final regions = <Rect>[];
    // Keep a guide-sized view in both passes. The other scale alternates to
    // cover small items without running every scale on every frame.
    for (final fraction in [0.82, detail ? 0.40 : 0.58]) {
      final side = frame.shortestSide * fraction;
      final columns = (frame.width / side * 1.3).ceil().clamp(2, 4);
      final rows = (frame.height / side * 1.3).ceil().clamp(2, 5);
      regions.add(_square(frame, fraction, 0.5, 0.5));
      for (var row = 0; row < rows; row++) {
        for (var column = 0; column < columns; column++) {
          regions.add(
            _square(frame, fraction, column / (columns - 1), row / (rows - 1)),
          );
        }
      }
    }
    return regions.toSet().toList(growable: false);
  }

  static Rect _square(Size frame, double fraction, double x, double y) {
    final side = math.min(frame.width, frame.height) * fraction;
    final width = side / frame.width;
    final height = side / frame.height;
    final left = (1 - width) * x;
    final top = (1 - height) * y;
    return Rect.fromLTRB(
      left,
      top,
      math.min(1, left + width),
      math.min(1, top + height),
    );
  }

  Future<({String format, List<List<double>> vectors})> _describe(
    Uint8List jpeg,
    List<Rect> regions,
  ) async {
    if (jpeg.isEmpty) throw const FormatException('Missing camera frame');
    final result = await _channel.invokeMapMethod<String, dynamic>('describe', {
      'jpeg': jpeg,
      'regions': [
        for (final region in regions)
          [region.left, region.top, region.right, region.bottom],
      ],
    });
    final format = result?['format'];
    final values = result?['vectors'];
    if (format is! String ||
        values is! List ||
        values.length != regions.length) {
      throw const FormatException('Invalid visual features');
    }
    return (
      format: format,
      vectors: [
        for (final value in values)
          unitEmbedding(
            (value as List).cast<num>().map((n) => n.toDouble()).toList(),
          ),
      ],
    );
  }
}
