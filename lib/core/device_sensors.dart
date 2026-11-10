import 'dart:async';

import 'package:flutter/services.dart';

/// Ambient light and proximity, straight from the phone's sensors.
///
/// Both are delivered by a small event channel in `MainActivity.kt`. They need
/// no camera frame, so Cue can warn about darkness or a covered lens before
/// OCR has had a chance to fail.
///
/// iOS exposes no public ambient-light sensor, so there the streams stay
/// silent and Cue keeps using camera brightness alone. Every consumer must
/// therefore treat "no events" as normal.
class DeviceSensors {
  DeviceSensors._();

  static final DeviceSensors instance = DeviceSensors._();

  static const EventChannel _events = EventChannel('cue/sensors');
  static const MethodChannel _methods = MethodChannel('cue/device');

  final StreamController<double> _light = StreamController<double>.broadcast();
  final StreamController<bool> _near = StreamController<bool>.broadcast();

  StreamSubscription<dynamic>? _subscription;
  bool _started = false;
  Future<bool>? _depth;

  /// Ambient light in lux. Empty on phones without the sensor.
  Stream<double> get light => _light.stream;

  /// True while something is covering the proximity sensor (a pocket, a hand,
  /// a sleeve). Empty on phones without the sensor.
  Stream<bool> get proximityNear => _near.stream;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _subscription = _events.receiveBroadcastStream().listen(
        _onEvent,
        onError: (Object _) {
          // Missing plugin (iOS, tests) means "no sensors", not a crash.
        },
        cancelOnError: false,
      );
    } catch (_) {
      // Same reasoning: absence is a supported state.
    }
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Whether this phone can expose a depth stream at all.
  ///
  /// A capability check only: Android will not let a second camera session
  /// read depth while the Flutter camera plugin is running, so Cue still uses
  /// the bounding-box estimate. The answer decides whether a depth upgrade is
  /// worth building for this device.
  Future<bool> depthAvailable() {
    return _depth ??= _probeDepth();
  }

  Future<bool> _probeDepth() async {
    try {
      return await _methods.invokeMethod<bool>('depthAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    switch (event['kind']) {
      case 'light':
        final value = event['value'];
        if (value is num) _light.add(value.toDouble());
      case 'proximity':
        final near = event['near'];
        if (near is bool) _near.add(near);
    }
  }
}
