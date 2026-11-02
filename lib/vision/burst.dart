import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

/// One frame from a burst, with a measured sharpness score.
///
/// A frame is either a still image on disk ([path]) or a raw NV21 buffer
/// ([nv21]) sampled from the live camera stream. The stream path is far
/// faster: a full still capture costs hundreds of milliseconds, while a
/// streamed frame is already being produced for the preview.
class BurstFrame {
  const BurstFrame.nv21({
    required this.nv21,
    required this.width,
    required this.height,
    required this.rotation,
    required this.sharpness,
  }) : path = null;

  const BurstFrame.file({
    required this.path,
    required this.sharpness,
  }) : nv21 = null,
       width = 0,
       height = 0,
       rotation = 0;

  /// Still-image file, when the burst had to fall back to `takePicture`.
  final String? path;

  /// Raw NV21 buffer, when the frame came from the camera stream.
  final Uint8List? nv21;

  final int width;
  final int height;

  /// Degrees the frame must be turned to be upright for OCR.
  final int rotation;

  final double sharpness;
}

/// Takes [shots] frames as fast as the camera allows, scores every one for
/// sharpness, and returns the [keep] sharpest, best first.
///
/// The user cannot see that a photo came out blurred, so the phone takes ten
/// and chooses for them.
Future<List<BurstFrame>> captureBurst(
  CameraController controller, {
  int shots = 10,
  int keep = 3,
  void Function(int taken)? onProgress,
  bool Function()? isCancelled,
}) async {
  // Streaming is roughly an order of magnitude faster than ten stills, and
  // it is the only path that makes "ten snaps at one shot" feel instant.
  if (defaultTargetPlatform == TargetPlatform.android &&
      controller.supportsImageStreaming()) {
    final streamed = await _streamBurst(
      controller,
      shots: shots,
      keep: keep,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (streamed.isNotEmpty) return streamed;
  }

  return _stillBurst(
    controller,
    shots: shots,
    keep: keep,
    onProgress: onProgress,
    isCancelled: isCancelled,
  );
}

/// Samples frames from the live camera stream.
///
/// Only the best [keep] frames are held in memory; every other frame is
/// dropped immediately, so the burst does not allocate ten full-size buffers.
Future<List<BurstFrame>> _streamBurst(
  CameraController controller, {
  required int shots,
  required int keep,
  void Function(int taken)? onProgress,
  bool Function()? isCancelled,
}) async {
  final watch = Stopwatch()..start();
  final done = Completer<void>();
  final best = <BurstFrame>[];

  final rotation = _rotationFor(
    controller.description,
    controller.value.deviceOrientation,
  );

  var seen = 0;
  var lastSampledAt = -1000;
  var firstAt = -1;
  var lastAt = -1;
  var failed = false;

  void finish() {
    if (!done.isCompleted) done.complete();
  }

  try {
    await controller.startImageStream((image) {
      if (done.isCompleted) return;
      if (isCancelled?.call() ?? false) {
        finish();
        return;
      }

      // Frames arrive around 30 per second. Sampling at least 100 ms apart
      // gives ten genuinely different moments rather than ten copies of one.
      final now = watch.elapsedMilliseconds;
      if (now - lastSampledAt < 100) return;
      if (image.planes.isEmpty) return;

      final plane = image.planes.first;
      final score = _nv21Sharpness(
        plane.bytes,
        plane.bytesPerRow,
        image.width,
        image.height,
      );

      seen++;
      lastSampledAt = now;
      if (firstAt < 0) firstAt = now;
      lastAt = now;

      // The plugin hands out a fresh buffer per frame, but copy the few we
      // keep so a recycled buffer can never corrupt a chosen frame later.
      final frame = BurstFrame.nv21(
        nv21: Uint8List.fromList(plane.bytes),
        width: image.width,
        height: image.height,
        rotation: rotation,
        sharpness: score,
      );

      if (best.length < keep) {
        best.add(frame);
      } else {
        var worst = 0;
        for (var i = 1; i < best.length; i++) {
          if (best[i].sharpness < best[worst].sharpness) worst = i;
        }
        if (score > best[worst].sharpness) best[worst] = frame;
      }

      onProgress?.call(seen < shots ? seen : shots);

      if (seen >= shots) finish();
    });
  } catch (_) {
    failed = true;
  }

  if (!failed) {
    final timeout = Timer(const Duration(seconds: 5), finish);
    try {
      await done.future;
    } finally {
      timeout.cancel();
    }
  }

  try {
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  } catch (_) {
    // The camera is being torn down, or the stream never started.
  }

  if (failed || best.isEmpty) return const [];

  best.sort((a, b) => b.sharpness.compareTo(a.sharpness));
  debugPrint(
    'burst: $seen frames from stream in ${watch.elapsedMilliseconds}ms '
    '(first $firstAt, last $lastAt, rotation $rotation), '
    'best sharpness ${best.first.sharpness.toStringAsFixed(1)}',
  );
  return best;
}

/// Fallback for platforms without image streaming: take ten stills.
///
/// Scoring starts as soon as each photo lands, so it overlaps with the next
/// capture instead of running after all ten.
Future<List<BurstFrame>> _stillBurst(
  CameraController controller, {
  required int shots,
  required int keep,
  void Function(int taken)? onProgress,
  bool Function()? isCancelled,
}) async {
  final watch = Stopwatch()..start();
  final captured = <XFile>[];
  final scoring = <Future<BurstFrame>>[];

  for (var i = 0; i < shots; i++) {
    if (isCancelled?.call() ?? false) break;
    try {
      final file = await controller.takePicture();
      captured.add(file);

      scoring.add(
        compute(_sharpnessAtPath, file.path).then(
          (score) => BurstFrame.file(path: file.path, sharpness: score),
        ),
      );

      onProgress?.call(i + 1);
    } catch (_) {
      // A dropped frame is not fatal: the rest of the burst still counts.
    }
  }

  if (captured.isEmpty) return const [];

  final captureMs = watch.elapsedMilliseconds;
  final scored = await Future.wait(scoring);
  debugPrint(
    'burst: ${captured.length} stills in ${captureMs}ms, '
    'scored in ${watch.elapsedMilliseconds}ms',
  );

  scored.sort((a, b) => b.sharpness.compareTo(a.sharpness));
  final kept = scored.take(keep).toList(growable: false);

  // Delete the frames nobody will use. On a mid-range phone, ten photos is
  // several megabytes, and this runs every time the user presses capture.
  final keptPaths = kept.map((f) => f.path).toSet();
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

/// Sharpness of an NV21 frame, measured on its luma plane.
///
/// This runs on the UI isolate, so it samples a grid about 160 pixels wide
/// instead of every pixel: fast enough for 30 frames a second, and consistent,
/// because all frames from one camera have the same size.
double _nv21Sharpness(Uint8List luma, int rowStride, int width, int height) {
  if (width < 3 || height < 3) return 0;

  final step = (width ~/ 160).clamp(1, 64);
  var sum = 0.0;
  var sumSquares = 0.0;
  var count = 0;

  for (var y = step; y < height - step; y += step) {
    final row = y * rowStride;
    final up = (y - step) * rowStride;
    final down = (y + step) * rowStride;

    for (var x = step; x < width - step; x += step) {
      final laplacian = luma[row + x - step] +
          luma[row + x + step] +
          luma[up + x] +
          luma[down + x] -
          (4 * luma[row + x]);

      sum += laplacian;
      sumSquares += laplacian * laplacian;
      count++;
    }
  }

  if (count == 0) return 0;
  final mean = sum / count;
  return (sumSquares / count) - (mean * mean);
}

/// Runs in a background isolate. Returns 0 for an unreadable file.
double _sharpnessAtPath(String path) {
  try {
    final bytes = File(path).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return 0;

    // Score at low resolution. 160 px is enough to tell sharp from blurred and
    // is about four times faster than 320 px.
    final small = img.copyResize(decoded, width: 160);
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

/// How far a streamed frame must be turned to be upright.
///
/// Streamed buffers are in the sensor's own orientation, usually landscape.
/// This is the same compensation ML Kit's own camera sample uses.
int _rotationFor(
  CameraDescription description,
  DeviceOrientation orientation,
) {
  final deviceRotation = switch (orientation) {
    DeviceOrientation.portraitUp => 0,
    DeviceOrientation.landscapeLeft => 90,
    DeviceOrientation.portraitDown => 180,
    DeviceOrientation.landscapeRight => 270,
  };

  if (description.lensDirection == CameraLensDirection.front) {
    return (description.sensorOrientation + deviceRotation) % 360;
  }
  return (description.sensorOrientation - deviceRotation + 360) % 360;
}
