import 'frame_metrics.dart';
import 'reading_quality.dart';

/// What kind of scene the camera is looking at.
///
/// The router exists so the rest of the pipeline can be written against a
/// stable interface: today it is rule-based and OCR-assisted, later FR-13
/// replaces its body with an on-device classifier without changing the callers.
enum SceneKind {
  /// Word-shaped marks: hand the frame to reading.
  text,

  /// Something is in view, but there are no readable words in it.
  notText,

  /// The frame cannot be judged: too dark, too blurred, or no frame at all.
  unclear,
}

class SceneDecision {
  const SceneDecision(this.kind, {this.reason});

  final SceneKind kind;

  /// Why the decision was made, for the debug log and tests.
  final String? reason;

  @override
  String toString() =>
      'SceneKind.${kind.name}${reason == null ? '' : ' ($reason)'}';
}

/// Rule-based scene router, version 1.
///
/// A full frame classifier is FR-13. Until that model exists, the cheapest
/// honest rule is: run the text recogniser, then ask whether what it returned
/// looks like words. That costs one OCR pass on non-text scenes, but it never
/// invents a label and it gives FR-13 a seam to slot into.
class SceneRouter {
  const SceneRouter();

  SceneDecision decide({required FrameMetrics metrics, required String text}) {
    if (metrics.isTooDark) {
      return const SceneDecision(SceneKind.unclear, reason: 'too dark');
    }
    if (metrics.isTooBlurry) {
      return const SceneDecision(SceneKind.unclear, reason: 'too blurry');
    }

    final clean = text.trim();
    if (clean.isEmpty) {
      return const SceneDecision(SceneKind.notText, reason: 'no words found');
    }
    if (!looksLikeText(clean)) {
      return const SceneDecision(SceneKind.notText, reason: 'not word-shaped');
    }
    return const SceneDecision(SceneKind.text);
  }
}

/// What the user has told Cue to look for.
///
/// The live screen starts in [text] because that is the only handler that is
/// built. Swipe left or right cycles through the choices the specification
/// names; the unbuilt ones answer honestly instead of pretending to see.
enum Interpretation {
  text('Text'),
  object('Object'),
  banknote('Banknote'),
  screen('Screen');

  const Interpretation(this.label);

  final String label;

  Interpretation get next => values[(index + 1) % values.length];

  Interpretation get previous =>
      values[(index - 1 + values.length) % values.length];

  bool get isBuilt => this == Interpretation.text;
}
