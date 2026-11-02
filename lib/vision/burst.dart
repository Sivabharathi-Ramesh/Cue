import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// One photo from a burst, with a measured sharpness score.
class BurstFrame {
  const BurstFrame({required this.file, required this.sharpness});

  final XFile file;
  final double sharpness;

  @override
  String toString() =>
      '${file.path} (sharpness ${sharpness.toStringAsFixed(1)})';
}

/// Takes [shots] photos as fast as the camera allows, scores every one for
/// sharpness, and returns the [keep] sharpest, best first.
///
/// The user cannot see that a photo came out blurred, so the phone takes ten
/// and chooses for them. The discarded files are deleted to save space.
Future<List<BurstFrame>> captureBurst(
  CameraController controller, {
  int shots = 10,
  int keep = 3,
  void Function(int taken)? onProgress,
}) async {
  final captured = <XFile>[];

  for (var i = 0; i < shots; i++) {
    try {
      captured.add(await controller.takePicture());
      onProgress?.call(i + 1);
    } catch (_) {
      // A dropped frame is not fatal: the rest of the burst still counts.
    }
  }

  if (captured.isEmpty) return const [];

  final scored = <BurstFrame>[];
  for (final file in captured) {
    final score = await compute(_sharpnessAtPath, file.path);
    scored.add(BurstFrame(file: file, sharpness: score));
  }

  scored.sort((a, b) => b.sharpness.compareTo(a.sharpness));
  final kept = scored.take(keep).toList(growable: false);

  // Delete the frames nobody will use. On a mid-range phone, ten photos is
  // several megabytes, and this runs every time the user presses capture.
  final keptPaths = kept.map((f) => f.file.path).toSet();
  for (final file in captured) {
    if (!keptPaths.contains(file.path)) {
      try {
        await File(file.path).delete();
      } catch (_) {
        // Temp file already gone, or not ours. Nothing to do.
      }
    }
  }

  return kept;
}

/// Runs in a background isolate. Returns 0 for an unreadable file.
double _sharpnessAtPath(String path) {
  try {
    final bytes = File(path).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return 0;

    // Score at low resolution: the result barely changes, and it is roughly
    // 100x faster than working on a full 12 megapixel frame.
    final small = img.copyResize(decoded, width: 320);
    final grey = img.grayscale(small);

    return _laplacianVariance(grey);
  } catch (_) {
    return 0;
  }
}

/// Variance of the Laplacian is the standard cheap blur metric.
///
/// A sharp photo has strong edges, so neighbouring pixels differ a lot and the
/// variance is high. A blurred photo is smooth everywhere and the variance is
/// near zero.
double _laplacianVariance(img.Image grey) {
  final w = grey.width;
  final h = grey.height;
  if (w < 3 || h < 3) return 0;

  var sum = 0.0;
  var sumSquares = 0.0;
  var count = 0;

  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final centre = grey.getPixel(x, y).r.toDouble();
      final left = grey.getPixel(x - 1, y).r.toDouble();
      final right = grey.getPixel(x + 1, y).r.toDouble();
      final up = grey.getPixel(x, y - 1).r.toDouble();
      final down = grey.getPixel(x, y + 1).r.toDouble();

      final laplacian = (left + right + up + down) - (4 * centre);

      sum += laplacian;
      sumSquares += laplacian * laplacian;
      count++;
    }
  }

  if (count == 0) return 0;
  final mean = sum / count;
  return (sumSquares / count) - (mean * mean);
}
