import 'package:cue/core/motion_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
