import 'package:cue/live/frame_metrics.dart';
import 'package:cue/live/scene_router.dart';
import 'package:flutter_test/flutter_test.dart';

FrameMetrics _frame({double brightness = 120, double sharpness = 120}) {
  return FrameMetrics(
    brightness: brightness,
    sharpness: sharpness,
    change: 0.5,
    width: 720,
    height: 1280,
  );
}

void main() {
  const router = SceneRouter();

  group('the scene router separates words from everything else', () {
    test('a clear printed page is text', () {
      final decision = router.decide(
        metrics: _frame(),
        text: 'The quick brown fox jumps over the lazy dog.',
      );
      expect(decision.kind, SceneKind.text);
      expect(decision.reason, isNull);
    });

    test('a bright frame with no words is not text', () {
      final decision = router.decide(metrics: _frame(), text: '');
      expect(decision.kind, SceneKind.notText);
      expect(decision.reason, 'no words found');
    });

    test('handwriting noise is not text', () {
      final decision = router.decide(metrics: _frame(), text: 'rnln fflrt');
      expect(decision.kind, SceneKind.notText);
      expect(decision.reason, 'not word-shaped');
    });

    test('a dark frame is unclear and takes priority over empty text', () {
      final decision = router.decide(metrics: _frame(brightness: 20), text: '');
      expect(decision.kind, SceneKind.unclear);
      expect(decision.reason, 'too dark');
    });

    test('a blurred frame is unclear, not a scene', () {
      final decision = router.decide(
        metrics: _frame(sharpness: 5),
        text: 'The quick brown fox',
      );
      expect(decision.kind, SceneKind.unclear);
      expect(decision.reason, 'too blurry');
    });

    test('a receipt of numbers and short labels is text', () {
      final decision = router.decide(
        metrics: _frame(),
        text: 'TOTAL 42.50\nVAT 8.50\nCARD 1234',
      );
      expect(decision.kind, SceneKind.text);
    });
  });

  group('interpretation cycling', () {
    test('forward follows the specification order and wraps', () {
      expect(Interpretation.text.next, Interpretation.object);
      expect(Interpretation.object.next, Interpretation.banknote);
      expect(Interpretation.banknote.next, Interpretation.screen);
      expect(Interpretation.screen.next, Interpretation.text);
    });

    test('backward is the exact reverse', () {
      expect(Interpretation.text.previous, Interpretation.screen);
      expect(Interpretation.screen.previous, Interpretation.banknote);
      expect(Interpretation.banknote.previous, Interpretation.object);
      expect(Interpretation.object.previous, Interpretation.text);
    });

    test('only text has a built handler in this build', () {
      expect(Interpretation.text.isBuilt, isTrue);
      expect(Interpretation.object.isBuilt, isFalse);
      expect(Interpretation.banknote.isBuilt, isFalse);
      expect(Interpretation.screen.isBuilt, isFalse);
    });
  });
}
