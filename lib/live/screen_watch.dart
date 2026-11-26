import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import '../vision/frame_source.dart';

enum ScreenWatchNotice { movement, unchanged, unclear }

/// Observes a steady camera view of a display without relying on OCR.
class ScreenWatch {
  static const unchangedAfter = Duration(seconds: 15);
  static const _unclearAfter = Duration(seconds: 4);
  static const _sampleInterval = Duration(milliseconds: 160);
  static const _sampleGap = Duration(milliseconds: 900);
  static const _movementWindow = Duration(milliseconds: 900);
  static const _side = 72;
  static const _sampleCount = _side * _side;
  // Sample the middle more densely because a loading indicator can be small.
  static final _axis = List<double>.generate(_side, (index) {
    final position = (index + 0.5) / _side - 0.5;
    return 0.5 + position * (0.44 + 0.88 * position.abs());
  });

  DateTime? _sampledAt;
  (String, int, int, DeviceOrientation)? _view;
  Uint8List? _previous;
  DateTime? _lastChangeAt;
  DateTime? _lastMovementAt;
  DateTime? _unclearSince;
  int _movementSamples = 0;
  ScreenWatchNotice? _lastNotice;

  ScreenWatchNotice? observe(
    CameraFrame frame,
    DateTime now, {
    required bool phoneMoving,
    required bool canAnnounce,
  }) {
    if (phoneMoving) {
      _loseView();
      _sampledAt = null;
      _unclearSince = null;
      return null;
    }
    final elapsed = _sampledAt == null ? null : now.difference(_sampledAt!);
    if (elapsed != null && elapsed < _sampleInterval) return null;
    if (elapsed != null && elapsed > _sampleGap) {
      _loseView();
      _unclearSince = null;
    }
    _sampledAt = now;

    final image = frame.image;
    final view = (
      frame.description.name,
      image.width,
      image.height,
      frame.deviceOrientation,
    );
    if (_view != view) {
      _loseView();
      _unclearSince = null;
      _view = view;
    }
    final sample = _sample(image);
    if (sample == null) {
      _loseView();
      final since = _unclearSince ??= now;
      return now.difference(since) >= _unclearAfter
          ? _report(ScreenWatchNotice.unclear, canAnnounce)
          : null;
    }
    _unclearSince = null;

    final previous = _previous;
    _previous = sample;
    final lastChange = _lastChangeAt ??= now;
    if (previous == null) return null;

    final (changed, bordersChanged) = _compare(previous, sample);
    // Widespread differences can be a camera shift or a new view. Either
    // invalidates the elapsed stillness time.
    if (changed > _sampleCount * 0.22 || bordersChanged > 160) {
      _lastChangeAt = now;
      _lastMovementAt = null;
      _movementSamples = 0;
      return null;
    }
    if (changed >= 3) {
      final lastMovement = _lastMovementAt;
      if (lastMovement == null ||
          now.difference(lastMovement) > _movementWindow) {
        _movementSamples = 0;
      }
      _movementSamples++;
      _lastChangeAt = now;
      _lastMovementAt = now;
    }
    final lastMovement = _lastMovementAt;
    if (_movementSamples >= 3 &&
        lastMovement != null &&
        now.difference(lastMovement) <= _movementWindow) {
      return _report(ScreenWatchNotice.movement, canAnnounce);
    }
    if (changed < 3 && now.difference(lastChange) >= unchangedAfter) {
      return _report(ScreenWatchNotice.unchanged, canAnnounce);
    }
    return null;
  }

  ScreenWatchNotice? _report(ScreenWatchNotice notice, bool canAnnounce) {
    if (!canAnnounce || _lastNotice == notice) return null;
    _lastNotice = notice;
    return notice;
  }

  void _loseView() {
    _previous = null;
    _lastChangeAt = null;
    _lastMovementAt = null;
    _movementSamples = 0;
  }

  /// Samples the central display area from the raw camera plane.
  static Uint8List? _sample(CameraImage image) {
    if (image.width < 16 || image.height < 16 || image.planes.isEmpty) {
      return null;
    }
    final plane = image.planes.first;
    final bgra = image.format.group == ImageFormatGroup.bgra8888;
    final stride = bgra ? 4 : plane.bytesPerPixel ?? 1;
    final row = plane.bytesPerRow;
    if (stride < 1 || row < 1) return null;
    final bytes = plane.bytes;
    final end = (image.height - 1) * row + (image.width - 1) * stride;
    if (bytes.length < end + (bgra ? 3 : 1)) return null;

    final sample = Uint8List(_sampleCount);
    var minimum = 255;
    var maximum = 0;
    for (var y = 0; y < _side; y++) {
      final sensorY = (image.height * _axis[y]).floor();
      for (var x = 0; x < _side; x++) {
        final sensorX = (image.width * _axis[x]).floor();
        final offset = sensorY * row + sensorX * stride;
        final luma = bgra
            ? (77 * bytes[offset + 2] +
                      150 * bytes[offset + 1] +
                      29 * bytes[offset]) ~/
                  256
            : bytes[offset];
        sample[y * _side + x] = luma;
        if (luma < minimum) minimum = luma;
        if (luma > maximum) maximum = luma;
      }
    }
    return maximum - minimum >= 24 ? sample : null;
  }

  /// Removes brightness shifts across rows and columns before counting
  /// changes. This discounts exposure changes and bands from screen refresh.
  static (int, int) _compare(Uint8List previous, Uint8List sample) {
    final rows = List<int>.filled(_side, 0);
    final columns = List<int>.filled(_side, 0);
    var total = 0;
    for (var y = 0; y < _side; y++) {
      for (var x = 0; x < _side; x++) {
        final i = y * _side + x;
        final delta = sample[i] - previous[i];
        rows[y] += delta;
        columns[x] += delta;
        total += delta;
      }
    }
    final mean = total / _sampleCount;
    var changed = 0;
    var bordersChanged = 0;
    for (var y = 0; y < _side; y++) {
      for (var x = 0; x < _side; x++) {
        final i = y * _side + x;
        final delta = sample[i] - previous[i];
        final residual = delta - (rows[y] + columns[x]) / _side + mean;
        if (residual.abs() < 16) continue;
        changed++;
        if (x < 8 || x >= _side - 8 || y < 8 || y >= _side - 8) {
          bordersChanged++;
        }
      }
    }
    return (changed, bordersChanged);
  }
}
