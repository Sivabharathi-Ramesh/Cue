import 'dart:ui';

import 'package:cue/live/aiming_coach.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 11, 3, 12);

  TextLayout layout({
    double coverage = 0.08,
    double centerX = 0.5,
    double heightRatio = 0.12,
    int wordCount = 12,
  }) {
    return TextLayout(
      coverage: coverage,
      centerX: centerX,
      heightRatio: heightRatio,
      wordCount: wordCount,
    );
  }

  test('darkness wins over every other cue', () {
    final coach = AimingCoach();
    final cue = coach.evaluate(
      brightness: 20,
      layout: layout(),
      now: start,
      recentlySpoken: false,
    );
    expect(cue, AimingCue.tooDark);
  });

  test('nothing found is spoken only after five seconds', () {
    final coach = AimingCoach();

    expect(
      coach.evaluate(
        brightness: 120,
        layout: null,
        now: start,
        recentlySpoken: false,
      ),
      isNull,
    );
    expect(
      coach.evaluate(
        brightness: 120,
        layout: null,
        now: start.add(const Duration(milliseconds: 4900)),
        recentlySpoken: false,
      ),
      isNull,
    );
    expect(
      coach.evaluate(
        brightness: 120,
        layout: null,
        now: start.add(const Duration(seconds: 5)),
        recentlySpoken: false,
      ),
      AimingCue.nothingFound,
    );
  });

  test('well-framed text produces no cue', () {
    final coach = AimingCoach();
    expect(
      coach.evaluate(
        brightness: 130,
        layout: layout(),
        now: start,
        recentlySpoken: false,
      ),
      isNull,
    );
  });

  test('too close, too far, left and right are detected', () {
    expect(
      AimingCoach().evaluate(
        brightness: 130,
        layout: layout(heightRatio: 0.7),
        now: start,
        recentlySpoken: false,
      ),
      AimingCue.tooClose,
    );

    expect(
      AimingCoach().evaluate(
        brightness: 130,
        layout: layout(coverage: 0.006),
        now: start,
        recentlySpoken: false,
      ),
      AimingCue.tooFar,
    );

    expect(
      AimingCoach().evaluate(
        brightness: 130,
        layout: layout(centerX: 0.2),
        now: start,
        recentlySpoken: false,
      ),
      AimingCue.moveLeft,
    );

    expect(
      AimingCoach().evaluate(
        brightness: 130,
        layout: layout(centerX: 0.8),
        now: start,
        recentlySpoken: false,
      ),
      AimingCue.moveRight,
    );
  });

  test('no framing advice while a result was just spoken', () {
    final coach = AimingCoach();
    expect(
      coach.evaluate(
        brightness: 130,
        layout: layout(centerX: 0.1, heightRatio: 0.8),
        now: start,
        recentlySpoken: true,
      ),
      isNull,
    );
  });

  test('the same cue is not repeated within its cooldown', () {
    final coach = AimingCoach();
    final first = coach.evaluate(
      brightness: 130,
      layout: layout(centerX: 0.1),
      now: start,
      recentlySpoken: false,
    );
    expect(first, AimingCue.moveLeft);

    final second = coach.evaluate(
      brightness: 130,
      layout: layout(centerX: 0.1),
      now: start.add(const Duration(seconds: 2)),
      recentlySpoken: false,
    );
    expect(second, isNull);
  });

  test('TextLayout unions block boxes and measures the centre', () {    final result = TextLayout.fromRects(
      <Rect>[
        const Rect.fromLTWH(100, 100, 200, 40),
        const Rect.fromLTWH(100, 150, 200, 40),
      ],
      const Size(1000, 1000),
      wordCount: 8,
    );

    expect(result.coverage, closeTo(0.018, 0.0001));
    expect(result.centerX, closeTo(0.2, 0.0001));
    expect(result.heightRatio, closeTo(0.04, 0.0001));
  });

  test('each aim problem has its own tone and side', () {
    // Left and right share a pitch on purpose: the side carries the meaning,
    // so they must differ in pan instead.
    final pitches = AimingCue.values.map((cue) => cue.toneHz).toSet();
    expect(pitches, hasLength(AimingCue.values.length - 1));
    expect(AimingCue.moveLeft.toneHz, AimingCue.moveRight.toneHz);

    expect(AimingCue.moveLeft.pan, lessThan(0));
    expect(AimingCue.moveRight.pan, greaterThan(0));
    expect(AimingCue.tooDark.pan, 0);
  });
}
