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
  final _helpShakes = StreamController<void>.broadcast();
  final _shake = HelpShakeDetector();

  StreamSubscription<GyroscopeEvent>? _gyro;
  StreamSubscription<AccelerometerEvent>? _accel;

  bool _started = false;
  bool _unsupported = false;
  bool _moving = false;
  DateTime? _lastMotionAt;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  // Low-pass filtered gravity vector, in device coordinates.
  bool _haveGravity = false;
  double _gravityX = 0;
  double _gravityY = -9.81;
  double _gravityZ = 0;

  bool get isMoving => _moving;

  double get rollDegrees => sample.value.rollDegrees;

  /// False on platforms or devices without a gyroscope.
  bool get isSupported => !_unsupported;

  /// One event per deliberate side-to-side shake gesture.
  Stream<void> get helpShakes => _helpShakes.stream;

  /// Let the user retry immediately when the live screen could not open Help.
  void rearmHelpShake() => _shake.reset();

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _unsupported = false;

    // Shake Help uses the accelerometer even on phones without a gyroscope.
    try {
      _accel = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 20),
      ).listen(_onAccelerometer, onError: _onAccelerometerError);
    } catch (error) {
      _onAccelerometerError(error);
    }
    try {
      _gyro = gyroscopeEventStream(
        samplingPeriod: const Duration(milliseconds: 80),
      ).listen(_onGyroscope, onError: _onGyroscopeError);
    } catch (error) {
      _onGyroscopeError(error);
    }
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    final gyro = _gyro;
    final accel = _accel;
    _gyro = null;
    _accel = null;
    _moving = false;
    _lastMotionAt = null;
    _haveGravity = false;
    _shake.reset();
    sample.value = MotionSample.idle;
    await Future.wait([
      if (gyro != null) gyro.cancel(),
      if (accel != null) accel.cancel(),
    ]);
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
    if (!event.x.isFinite || !event.y.isFinite || !event.z.isFinite) return;
    if (!_haveGravity) {
      _gravityX = event.x;
      _gravityY = event.y;
      _gravityZ = event.z;
      _haveGravity = true;
    } else {
      // Keep roughly the same smoothing at the faster accelerometer cadence.
      const alpha = 0.04;
      _gravityX += (event.x - _gravityX) * alpha;
      _gravityY += (event.y - _gravityY) * alpha;
      _gravityZ += (event.z - _gravityZ) * alpha;
    }
    if (_shake.observe(event, gravity: (_gravityX, _gravityY, _gravityZ))) {
      _helpShakes.add(null);
    }
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

  void _onGyroscopeError(Object _) {
    // No gyroscope (an emulator, a cheap tablet) means no motion gate. The
    // camera's own blur check still applies.
    _unsupported = true;
    _lastMotionAt = null;
    _moving = false;
  }

  void _onAccelerometerError(Object _) {
    _haveGravity = false;
    _shake.reset();
  }
}

/// Recognises two quick side-to-side shakes of the phone.
///
/// Three alternating bursts distinguish the start of two shakes from a
/// single pickup and stop. Projecting across gravity rejects vertical steps.
class HelpShakeDetector {
  static const double _minAcceleration = 5.5; // m/s²
  static const double _directionAlignment = 0.65;
  static const Duration _minPeakGap = Duration(milliseconds: 65);
  static const Duration _maxPeakGap = Duration(milliseconds: 360);
  static const Duration _cooldown = Duration(milliseconds: 2500);
  static const int _peaksRequired = 3;

  ({double x, double y, double z, DateTime time})? _lastPeak;
  DateTime? _lastShakeAt;
  int _peakCount = 0;

  bool observe(
    AccelerometerEvent event, {
    required (double, double, double) gravity,
  }) {
    final time = event.timestamp;
    final lastShake = _lastShakeAt;
    if (lastShake != null && time.difference(lastShake) < _cooldown) {
      return false;
    }

    final (gx, gy, gz) = gravity;
    final gravitySquared = gx * gx + gy * gy + gz * gz;
    if (gravitySquared < 1) return false;
    final vertical =
        (event.x * gx + event.y * gy + event.z * gz) / gravitySquared;
    final x = event.x - vertical * gx;
    final y = event.y - vertical * gy;
    final z = event.z - vertical * gz;
    final magnitude = math.sqrt(x * x + y * y + z * z);
    if (magnitude < _minAcceleration) return false;

    final direction = (
      x: x / magnitude,
      y: y / magnitude,
      z: z / magnitude,
      time: time,
    );
    var peakCount = 1;
    final previous = _lastPeak;
    if (previous != null) {
      final gap = time.difference(previous.time);
      if (gap < _minPeakGap) return false;
      if (gap <= _maxPeakGap) {
        final alignment =
            direction.x * previous.x +
            direction.y * previous.y +
            direction.z * previous.z;
        // Extra samples in the same swing and brief off-axis movements
        // leave the last real reversal available for the next swing.
        if (alignment > -_directionAlignment) return false;
        peakCount = _peakCount + 1;
      }
    }
    _lastPeak = direction;
    _peakCount = peakCount;
    if (peakCount < _peaksRequired) return false;

    _lastPeak = null;
    _peakCount = 0;
    _lastShakeAt = time;
    return true;
  }

  void reset() {
    _lastPeak = null;
    _lastShakeAt = null;
    _peakCount = 0;
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
