import 'dart:ui';

/// Where the recognised text sits inside the frame, in upright coordinates.
///
/// Built from ML Kit block boxes. Kept separate from ML Kit so the aiming
/// rules can be unit tested with plain rectangles.
class TextLayout {
  const TextLayout({
    required this.coverage,
    required this.centerX,
    required this.heightRatio,
    required this.wordCount,
  });

  /// Fraction of the frame covered by the union of all text blocks.
  final double coverage;

  /// Horizontal centre of the text, 0 (left edge) to 1 (right edge).
  final double centerX;

  /// Height of the tallest text block divided by the frame height.
  final double heightRatio;

  final int wordCount;

  factory TextLayout.fromRects(
    List<Rect> boxes,
    Size frameSize, {
    required int wordCount,
  }) {
    if (boxes.isEmpty || frameSize.width <= 0 || frameSize.height <= 0) {
      return TextLayout(
        coverage: 0,
        centerX: 0.5,
        heightRatio: 0,
        wordCount: wordCount,
      );
    }

    var union = boxes.first;
    var tallest = boxes.first.height;
    for (final box in boxes.skip(1)) {
      union = union.expandToInclude(box);
      if (box.height > tallest) tallest = box.height;
    }

    final frameArea = frameSize.width * frameSize.height;
    final coverage = frameArea <= 0 ? 0.0 : (union.width * union.height) / frameArea;

    return TextLayout(
      coverage: coverage.clamp(0.0, 1.0),
      centerX: (union.center.dx / frameSize.width).clamp(0.0, 1.0),
      heightRatio: (tallest / frameSize.height).clamp(0.0, 1.0),
      wordCount: wordCount,
    );
  }
}

enum AimingCue { tooDark, tooClose, tooFar, moveLeft, moveRight, nothingFound }

extension AimingCueSpeech on AimingCue {
  String get speech {
    switch (this) {
      case AimingCue.tooDark:
        return 'Too dark. Move to better light.';
      case AimingCue.tooClose:
        return 'Too close. Move the phone back.';
      case AimingCue.tooFar:
        return 'Too far. Move the phone closer.';
      case AimingCue.moveLeft:
        return 'Move left.';
      case AimingCue.moveRight:
        return 'Move right.';
      case AimingCue.nothingFound:
        return 'No text yet. Point at a page.';
    }
  }
}

extension AimingCueTone on AimingCue {
  /// Pitch for this problem, in hertz.
  ///
  /// Section 7 of the specification says the aim tone changes with the
  /// problem. Higher means "move that way", lower means "the problem is the
  /// scene": the user can learn the mapping without seeing the screen.
  double get toneHz {
    switch (this) {
      case AimingCue.tooDark:
        return 230;
      case AimingCue.tooClose:
        return 340;
      case AimingCue.tooFar:
        return 400;
      case AimingCue.moveLeft:
        return 330;
      case AimingCue.moveRight:
        return 330;
      case AimingCue.nothingFound:
        return 260;
    }
  }

  /// Stereo position, -1 (left) to 1 (right).
  ///
  /// "Move left" plays in the left ear, which is faster to act on than a
  /// sentence, especially with headphones. Everything else is centred.
  double get pan {
    switch (this) {
      case AimingCue.moveLeft:
        return -0.85;
      case AimingCue.moveRight:
        return 0.85;
      default:
        return 0;
    }
  }
}

/// Turns frame measurements into at most one short aiming sentence.
///
/// Rules are ordered by safety: darkness first, because no amount of moving
/// left will help, then "nothing found", then framing. Cues are rate limited
/// so the app cannot nag, and geometry cues are suppressed for a few seconds
/// after a successful read.
class AimingCoach {
  static const double darkThreshold = 45;

  DateTime? _lastTextAt;
  AimingCue? _lastCue;
  DateTime? _lastCueAt;

  AimingCue? evaluate({
    required double brightness,
    required TextLayout? layout,
    required DateTime now,
    required bool recentlySpoken,
  }) {
    if (brightness < darkThreshold) {
      return _emit(AimingCue.tooDark, now, const Duration(seconds: 4));
    }

    if (recentlySpoken) {
      _lastTextAt = now;
      return null;
    }

    final hasText =
        layout != null && layout.wordCount > 0 && layout.coverage > 0.004;

    if (!hasText) {
      _lastTextAt ??= now;
      if (now.difference(_lastTextAt!) >= const Duration(seconds: 5)) {
        return _emit(AimingCue.nothingFound, now, const Duration(seconds: 8));
      }
      return null;
    }

    _lastTextAt = now;

    // One word may simply be a logo. Framing advice needs a little context.
    if (layout.wordCount < 2) return null;

    if (layout.heightRatio > 0.55) {
      return _emit(AimingCue.tooClose, now, const Duration(seconds: 5));
    }
    if (layout.coverage < 0.012) {
      return _emit(AimingCue.tooFar, now, const Duration(seconds: 5));
    }
    if (layout.centerX < 0.35) {
      return _emit(AimingCue.moveLeft, now, const Duration(seconds: 4));
    }
    if (layout.centerX > 0.65) {
      return _emit(AimingCue.moveRight, now, const Duration(seconds: 4));
    }

    return null;
  }

  void reset() {
    _lastTextAt = null;
    _lastCue = null;
    _lastCueAt = null;
  }

  AimingCue? _emit(AimingCue cue, DateTime now, Duration cooldown) {
    if (_lastCueAt != null &&
        now.difference(_lastCueAt!) < const Duration(milliseconds: 1200)) {
      return null;
    }
    if (_lastCue == cue &&
        _lastCueAt != null &&
        now.difference(_lastCueAt!) < cooldown) {
      return null;
    }

    _lastCue = cue;
    _lastCueAt = now;
    return cue;
  }
}
