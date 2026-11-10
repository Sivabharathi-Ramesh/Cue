import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Which way the top of the phone should move to be level again.
enum TiltInstruction { toTheLeft, toTheRight }

/// A smoothed picture of how the phone is being held.
class MotionSample {
  const MotionSample({this.moving = false, this.rollDegrees = 0});

  /// True while the phone is being swung, walked with or shaken.
  final bool moving;

  /// Tilt around the viewing axis, in degrees. Zero is upright; positive
  /// means the top is leaning to the user's right.
  final double rollDegrees;

  static const MotionSample idle = MotionSample();
}

/// Watches the gyroscope and accelerometer so the pipeline can tell a blurry
/// hand from a blurry page.
///
/// Frame differencing cannot see motion on a blank wall: nothing changes, so
/// the pipeline thinks the scene is still while the phone is actually
/// swinging. The gyroscope knows better, and the accelerometer gives the roll
/// angle, which the user cannot see and therefore cannot correct.
class MotionMonitor {
  MotionMonitor._();

  static final MotionMonitor instance = MotionMonitor._();

  /// Radians per second above which the phone counts as moving (~15 deg/s).
  static const double _motionThreshold = 0.25;

  /// How long after the last movement the phone is still considered moving.
  static const Duration _motionHold = Duration(milliseconds: 450);

  final ValueNotifier<MotionSample> sample = ValueNotifier<MotionSample>(
    MotionSample.idle,
  );

  StreamSubscription<GyroscopeEvent>? _gyro;
  StreamSubscription<AccelerometerEvent>? _accel;

  bool _started = false;
  bool _unsupported = false;
  bool _moving = false;
  DateTime? _lastMotionAt;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  // Low-pass filtered gravity vector, in device coordinates.
  double _gravityX = 0;
  double _gravityY = -9.81;

  bool get isMoving => _moving;

  double get rollDegrees => sample.value.rollDegrees;

  /// False on platforms or devices without a gyroscope.
  bool get isSupported => !_unsupported;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      _gyro = gyroscopeEventStream(
        samplingPeriod: const Duration(milliseconds: 80),
      ).listen(_onGyroscope, onError: _onError);
      _accel = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 80),
      ).listen(_onAccelerometer, onError: _onError);
    } catch (_) {
      _unsupported = true;
    }
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _gyro?.cancel();
    await _accel?.cancel();
    _gyro = null;
    _accel = null;
    _moving = false;
    sample.value = MotionSample.idle;
  }

  void _onGyroscope(GyroscopeEvent event) {
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    final now = DateTime.now();
    if (magnitude > _motionThreshold) {
      _lastMotionAt = now;
      _moving = true;
    }
    _emit(now);
  }

  void _onAccelerometer(AccelerometerEvent event) {
    const alpha = 0.15;
    _gravityX += (event.x - _gravityX) * alpha;
    _gravityY += (event.y - _gravityY) * alpha;
    _emit(DateTime.now());
  }

  void _emit(DateTime now) {
    final lastMotion = _lastMotionAt;
    _moving = lastMotion != null && now.difference(lastMotion) < _motionHold;

    // Ten updates a second is plenty for a hint, and keeps widget rebuilds
    // and pipeline reads cheap.
    if (now.difference(_lastEmit) < const Duration(milliseconds: 100)) return;
    _lastEmit = now;

    sample.value = MotionSample(
      moving: _moving,
      rollDegrees: rollDegreesFromGravity(_gravityX, _gravityY),
    );
  }

  void _onError(Object error) {
    // No gyroscope (an emulator, a cheap tablet) means no motion gate. The
    // camera's own blur check still applies.
    _unsupported = true;
    _moving = false;
  }
}

/// Roll angle in degrees from the accelerometer's gravity vector.
///
/// Device coordinates: x to the right of the screen, y to its top. Holding the
/// phone upright gives gravity (0, -9.81), so the result is zero; rotating the
/// top to the right makes it positive.
double rollDegreesFromGravity(double x, double y) {
  final angle = math.atan2(-x, -y) * 180 / math.pi;
  return angle;
}

/// The correction to suggest, or null when the phone is level enough.
///
/// Positive roll means the top is leaning right, so the user should move the
/// top to the left. Flat or inverted positions are ignored: roll is not a
/// meaningful instruction there.
TiltInstruction? tiltInstructionFor(
  double rollDegrees, {
  double threshold = 18,
  double ceiling = 75,
}) {
  if (rollDegrees.abs() > ceiling) return null;
  if (rollDegrees > threshold) return TiltInstruction.toTheLeft;
  if (rollDegrees < -threshold) return TiltInstruction.toTheRight;
  return null;
}
