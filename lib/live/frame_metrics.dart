import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Measurements taken from one camera frame before OCR sees it.
class FrameMetrics {
  const FrameMetrics({
    required this.brightness,
    required this.sharpness,
    required this.change,
    required this.width,
    required this.height,
  });

  /// Mean luminance of the Y plane, 0 (black) to 255 (white).
  final double brightness;

  /// Variance of the Laplacian. High means sharp edges; near zero means blur.
  final double sharpness;

  /// Mean absolute difference from the previous frame, 0 to 1.
  final double change;

  final int width;
  final int height;

  bool get isTooDark => brightness < 45;

  /// Below this Laplacian variance a frame is treated as blurred.
  static const double blurThreshold = 25;

  bool get isTooBlurry => sharpness < blurThreshold;

  @override
  String toString() =>
      'brightness ${brightness.toStringAsFixed(1)}, '
      'sharpness ${sharpness.toStringAsFixed(1)}, '
      'change ${change.toStringAsFixed(3)}';
}

/// Samples the Y (luminance) plane of camera frames.
///
/// Everything here works on the raw plane, never on a decoded JPEG. That is
/// what makes a 2-3 frame per second pipeline affordable on a mid-range phone:
/// no image decode, no allocation of a full RGB bitmap, just sampled reads.
class FrameSampler {
  static const int _thumbnailSize = 16;

  Uint8List? _previousThumbnail;

  /// Set by the pipeline the first time so frame one is never skipped as
  /// "unchanged". A null previous thumbnail produces change = 1.
  FrameMetrics sample(CameraImage image) {
    if (image.planes.isEmpty || image.width < 3 || image.height < 3) {
      return FrameMetrics(
        brightness: 0,
        sharpness: 0,
        change: 1,
        width: image.width,
        height: image.height,
      );
    }

    final plane = image.planes.first;
    final bytes = plane.bytes;
    final width = image.width;
    final height = image.height;
    final rowStride = plane.bytesPerRow;
    final pixelStride = plane.bytesPerPixel ?? 1;

    final isBgra =
        defaultTargetPlatform == TargetPlatform.iOS &&
        image.planes.length == 1 &&
        rowStride >= width * 4;
    if (isBgra) {
      final brightness = _meanLuminanceBgra(bytes, width, height, rowStride);
      final sharpness = _laplacianVarianceBgra(bytes, width, height, rowStride);
      final thumbnail = _thumbnailBgra(bytes, width, height, rowStride);
      final change = _difference(_previousThumbnail, thumbnail);
      _previousThumbnail = thumbnail;

      return FrameMetrics(
        brightness: brightness,
        sharpness: sharpness,
        change: change,
        width: width,
        height: height,
      );
    }

    final brightness = _meanLuminance(
      bytes,
      width,
      height,
      rowStride,
      pixelStride,
    );
    final sharpness = _laplacianVariance(
      bytes,
      width,
      height,
      rowStride,
      pixelStride,
    );
    final thumbnail = _thumbnail(bytes, width, height, rowStride, pixelStride);
    final change = _difference(_previousThumbnail, thumbnail);
    _previousThumbnail = thumbnail;

    return FrameMetrics(
      brightness: brightness,
      sharpness: sharpness,
      change: change,
      width: width,
      height: height,
    );
  }

  void reset() {
    _previousThumbnail = null;
  }

  /// Approximate luma of one BGRA pixel, 0–255.
  ///
  /// iOS BGRA8888 frames are treated as "not NV21"; scanning the alpha byte
  /// as if it were Y would inflate the darkness score and hide every
  /// too-dark frame.
  double _bgraLuma(Uint8List bytes, int row, int x) {
    final base = row + x * 4;
    if (base + 2 >= bytes.length) return 0;
    return 0.114 * bytes[base] +
        0.587 * bytes[base + 1] +
        0.299 * bytes[base + 2];
  }

  double _meanLuminanceBgra(
    Uint8List bytes,
    int width,
    int height,
    int rowStride,
  ) {
    const step = 4;
    var sum = 0.0;
    var count = 0;

    for (var y = 0; y < height; y += step) {
      final row = y * rowStride;
      for (var x = 0; x < width; x += step) {
        sum += _bgraLuma(bytes, row, x);
        count++;
      }
    }

    return count == 0 ? 0 : sum / count;
  }

  double _laplacianVarianceBgra(
    Uint8List bytes,
    int width,
    int height,
    int rowStride,
  ) {
    const step = 2;
    var sum = 0.0;
    var sumSquares = 0.0;
    var count = 0;

    for (var y = step; y < height - step; y += step) {
      final row = y * rowStride;
      final up = (y - step) * rowStride;
      final down = (y + step) * rowStride;

      for (var x = step; x < width - step; x += step) {
        final centre = _bgraLuma(bytes, row, x);
        final left = _bgraLuma(bytes, row, x - step);
        final right = _bgraLuma(bytes, row, x + step);
        final upValue = _bgraLuma(bytes, up, x);
        final downValue = _bgraLuma(bytes, down, x);

        final laplacian = left + right + upValue + downValue - 4 * centre;
        sum += laplacian;
        sumSquares += laplacian * laplacian;
        count++;
      }
    }

    if (count == 0) return 0;
    final mean = sum / count;
    return (sumSquares / count) - (mean * mean);
  }

  Uint8List _thumbnailBgra(
    Uint8List bytes,
    int width,
    int height,
    int rowStride,
  ) {
    final thumbnail = Uint8List(_thumbnailSize * _thumbnailSize);
    final blockWidth = width / _thumbnailSize;
    final blockHeight = height / _thumbnailSize;

    for (var ty = 0; ty < _thumbnailSize; ty++) {
      final startY = (ty * blockHeight).floor();
      final endY = ((ty + 1) * blockHeight).floor().clamp(startY + 1, height);

      for (var tx = 0; tx < _thumbnailSize; tx++) {
        final startX = (tx * blockWidth).floor();
        final endX = ((tx + 1) * blockWidth).floor().clamp(startX + 1, width);

        var sum = 0.0;
        var count = 0;
        for (var y = startY; y < endY; y += 2) {
          final row = y * rowStride;
          for (var x = startX; x < endX; x += 2) {
            sum += _bgraLuma(bytes, row, x);
            count++;
          }
        }

        thumbnail[ty * _thumbnailSize + tx] = count == 0
            ? 0
            : (sum / count).round();
      }
    }

    return thumbnail;
  }

  double _meanLuminance(
    Uint8List bytes,
    int width,
    int height,
    int rowStride,
    int pixelStride,
  ) {
    const step = 4;
    var sum = 0;
    var count = 0;

    for (var y = 0; y < height; y += step) {
      final row = y * rowStride;
      for (var x = 0; x < width; x += step) {
        final index = row + x * pixelStride;
        if (index >= bytes.length) continue;
        sum += bytes[index];
        count++;
      }
    }

    return count == 0 ? 0 : sum / count;
  }

  /// Variance of the Laplacian, sampled every other pixel.
  ///
  /// A sharp page has strong black/white edges, so neighbouring pixels differ
  /// a lot and the variance is high. A blurred or moving page is smooth and
  /// the variance collapses toward zero.
  double _laplacianVariance(
    Uint8List bytes,
    int width,
    int height,
    int rowStride,
    int pixelStride,
  ) {
    const step = 2;
    var sum = 0.0;
    var sumSquares = 0.0;
    var count = 0;

    for (var y = step; y < height - step; y += step) {
      final row = y * rowStride;
      final up = (y - step) * rowStride;
      final down = (y + step) * rowStride;

      for (var x = step; x < width - step; x += step) {
        final centreIndex = row + x * pixelStride;
        final leftIndex = row + (x - step) * pixelStride;
        final rightIndex = row + (x + step) * pixelStride;
        final upIndex = up + x * pixelStride;
        final downIndex = down + x * pixelStride;

        if (downIndex >= bytes.length) continue;

        final laplacian =
            bytes[leftIndex] +
            bytes[rightIndex] +
            bytes[upIndex] +
            bytes[downIndex] -
            4 * bytes[centreIndex];

        sum += laplacian;
        sumSquares += laplacian * laplacian;
        count++;
      }
    }

    if (count == 0) return 0;
    final mean = sum / count;
    return (sumSquares / count) - (mean * mean);
  }

  Uint8List _thumbnail(
    Uint8List bytes,
    int width,
    int height,
    int rowStride,
    int pixelStride,
  ) {
    final thumbnail = Uint8List(_thumbnailSize * _thumbnailSize);
    final blockWidth = width / _thumbnailSize;
    final blockHeight = height / _thumbnailSize;

    for (var ty = 0; ty < _thumbnailSize; ty++) {
      final startY = (ty * blockHeight).floor();
      final endY = ((ty + 1) * blockHeight).floor().clamp(startY + 1, height);

      for (var tx = 0; tx < _thumbnailSize; tx++) {
        final startX = (tx * blockWidth).floor();
        final endX = ((tx + 1) * blockWidth).floor().clamp(startX + 1, width);

        var sum = 0;
        var count = 0;
        for (var y = startY; y < endY; y += 2) {
          final row = y * rowStride;
          for (var x = startX; x < endX; x += 2) {
            final index = row + x * pixelStride;
            if (index >= bytes.length) continue;
            sum += bytes[index];
            count++;
          }
        }

        thumbnail[ty * _thumbnailSize + tx] = count == 0
            ? 0
            : (sum / count).round();
      }
    }

    return thumbnail;
  }

  double _difference(Uint8List? previous, Uint8List current) {
    if (previous == null || previous.length != current.length) return 1;

    var sum = 0;
    for (var i = 0; i < current.length; i++) {
      sum += (current[i] - previous[i]).abs();
    }
    return sum / (current.length * 255);
  }
}
