import 'dart:math' as math;

import 'package:cue/core/motion_monitor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rollDegreesFromGravity', () {
    test('a phone held upright has zero roll', () {
      expect(rollDegreesFromGravity(0, -9.81), closeTo(0, 0.001));
    });

    test('the top leaning right is a positive roll', () {
      // Device gravity when the top has rotated to the user's right.
      expect(rollDegreesFromGravity(-9.81, 0), closeTo(90, 0.001));
    });

    test('the top leaning left is a negative roll', () {
      expect(rollDegreesFromGravity(9.81, 0), closeTo(-90, 0.001));
    });

    test('a diagonal hold reports the angle', () {
      final roll = rollDegreesFromGravity(-3.0, -8.5);
      expect(roll, greaterThan(15));
      expect(roll, lessThan(25));
    });
  });

  group('tiltInstructionFor', () {
    test('a level phone needs no correction', () {
      expect(tiltInstructionFor(0), isNull);
      expect(tiltInstructionFor(12), isNull);
      expect(tiltInstructionFor(-12), isNull);
    });

    test('top leaning right tells the user to move it left', () {
      expect(tiltInstructionFor(25), TiltInstruction.toTheLeft);
    });

    test('top leaning left tells the user to move it right', () {
      expect(tiltInstructionFor(-25), TiltInstruction.toTheRight);
    });

    test('a flat or inverted phone gives no tilt advice', () {
      expect(tiltInstructionFor(90), isNull);
      expect(tiltInstructionFor(-120), isNull);
      expect(tiltInstructionFor(180), isNull);
    });

    test('custom thresholds are respected', () {
      expect(tiltInstructionFor(20, threshold: 25), isNull);
      expect(tiltInstructionFor(20, threshold: 10), TiltInstruction.toTheLeft);
    });
  });

  group('MotionSample', () {
    test('starts idle and level', () {
      expect(MotionSample.idle.moving, isFalse);
      expect(MotionSample.idle.rollDegrees, 0);
    });
  });

  group('HelpShakeDetector', () {
    final start = DateTime.utc(2026, 11, 23);
    const gravity = (0.0, -9.81, 0.0);
    late HelpShakeDetector detector;

    setUp(() => detector = HelpShakeDetector());

    bool sample(
      int milliseconds, {
      double x = 0,
      double y = -9.81,
      double z = 0,
    }) {
      return detector.observe(
        AccelerometerEvent(
          x,
          y,
          z,
          start.add(Duration(milliseconds: milliseconds)),
        ),
        gravity: gravity,
      );
    }

    List<bool> shake(int start) => [
      sample(start, x: 11),
      sample(start + 160, x: -11),
      sample(start + 320, x: 11),
    ];

    test('opens Help on the third alternating burst', () {
      expect(shake(0), [false, false, true]);
    });

    test('accepts gentler swings and tolerates brief off-axis motion', () {
      expect(sample(0, x: 6), isFalse);
      expect(sample(100, x: 6.2), isFalse);
      expect(sample(175, z: 6.5), isFalse);
      expect(sample(330, x: -6), isFalse);
      expect(sample(450, z: -6.5), isFalse);
      expect(sample(660, x: 6.2), isTrue);
    });

    test('ignores a pickup, ordinary panning and vertical steps', () {
      expect(sample(0, x: 12), isFalse);
      expect(sample(40, x: -12), isFalse);
      expect(sample(130, x: -10), isFalse);
      for (var i = 0; i < 12; i++) {
        final direction = i.isEven ? 1 : -1;
        expect(
          sample(300 + i * 160, x: 3.5 * direction, y: -9.81 + 11 * direction),
          isFalse,
        );
      }
    });

    test('does not combine slow swings into a shake', () {
      for (var i = 0; i < 6; i++) {
        expect(sample(i * 400, x: i.isEven ? 11 : -11), isFalse);
      }
    });

    test('ignores repeat shakes during the cooldown, then re-arms', () {
      expect(shake(0).last, isTrue);
      expect(shake(1500), everyElement(isFalse));
      expect(shake(3000), [false, false, true]);
    });
  });

  test(
    'a gentle shake emits Help even on a phone without a gyroscope',
    () async {
      const prefix = 'dev.fluttercommunity.plus/sensors';
      const accelerometer = MethodChannel('$prefix/accelerometer');
      const gyroscope = MethodChannel('$prefix/gyroscope');
      const channels = [
        MethodChannel('$prefix/method'),
        gyroscope,
        accelerometer,
      ];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final channel in channels) {
        messenger.setMockMethodCallHandler(channel, (_) async => null);
      }

      final monitor = MotionMonitor.instance;
      var shakes = 0;
      final subscription = monitor.helpShakes.listen((_) => shakes++);
      addTearDown(() async {
        await monitor.stop();
        await subscription.cancel();
        for (final channel in channels) {
          messenger.setMockMethodCallHandler(channel, null);
        }
      });

      await monitor.start();
      const codec = StandardMethodCodec();
      await messenger.handlePlatformMessage(
        gyroscope.name,
        codec.encodeErrorEnvelope(code: 'NO_SENSOR'),
        null,
      );
      final start = DateTime.utc(2026, 11, 23).microsecondsSinceEpoch;
      Future<void> moveSideToSide(int startingMs) async {
        for (var milliseconds = 0; milliseconds <= 760; milliseconds += 20) {
          final x = 6.8 * math.sin(2 * math.pi * milliseconds / 380);
          await messenger.handlePlatformMessage(
            accelerometer.name,
            codec.encodeSuccessEnvelope([
              x,
              -9.81,
              0.0,
              (start + (startingMs + milliseconds) * 1000).toDouble(),
            ]),
            null,
          );
        }
        await Future<void>.delayed(Duration.zero);
      }

      await moveSideToSide(0);
      expect(monitor.isSupported, isFalse);
      expect(shakes, 1);

      // The screen calls this when a dialog or the microphone blocked Help.
      monitor.rearmHelpShake();
      await moveSideToSide(900);
      expect(shakes, 2);
    },
  );
}
