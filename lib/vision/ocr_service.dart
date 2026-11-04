import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'burst.dart';

/// One live-camera OCR result, kept independent of the ML Kit result type so
/// the pipeline can hold it without importing plugin classes everywhere.
class OcrRead {
  const OcrRead({
    required this.text,
    required this.blocks,
    this.confidence,
  });

  final String text;
  final List<TextBlock> blocks;

  /// Mean recogniser confidence across the lines, 0–1, or null when the
  /// platform does not report one (iOS).
  ///
  /// Weighted by line length, so one confidently-read heading cannot mask a
  /// page of guesses. This is the number the honesty gate uses to decide
  /// whether a reading may be spoken at all.
  final double? confidence;

  bool get isEmpty => text.trim().isEmpty;
}

/// Turns a photo of text into words.
///
/// Runs entirely on the phone. No image is uploaded anywhere, which is what
/// the client asked for: "works with no signal".
class OcrService {
  OcrService._();

  static final OcrService instance = OcrService._();

  TextRecognizer? _latin;

  /// ML Kit holds one native recogniser. Warm-up, the Read screen and the
  /// live pipeline must not call it at the same time, so every operation is
  /// queued behind the previous one.
  Future<void> _tail = Future<void>.value();

  TextRecognizer get _recognizer =>
      _latin ??= TextRecognizer(script: TextRecognitionScript.latin);

  Future<T> _serialise<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// Loads the recognition model before the user needs it.
  ///
  /// The first call into ML Kit can take several seconds while the model is
  /// loaded. Doing it once when a camera screen opens hides that behind
  /// aiming the camera, instead of making the first reading feel frozen.
  Future<void> warmUp() {
    return _serialise(() async {
      final recognizer = _recognizer;

      final watch = Stopwatch()..start();
      try {
        // A tiny blank frame is enough to force the model to load.
        const width = 64;
        const height = 64;
        final grey = Uint8List(width * height * 3 ~/ 2)
          ..fillRange(0, width * height, 0x80);

        await recognizer.processImage(
          InputImage.fromBytes(
            bytes: grey,
            metadata: InputImageMetadata(
              size: const Size(64, 64),
              rotation: InputImageRotation.rotation0deg,
              format: InputImageFormat.nv21,
              bytesPerRow: width,
            ),
          ),
        );
      } catch (_) {
        // Warming up is an optimisation. If it fails, the real call still
        // runs.
      }
      debugPrint('ocr: warmup ${watch.elapsedMilliseconds}ms');
    });
  }

  /// Reads text from a still image on disk, or a raw burst frame.
  /// Kept for the original Read screen.
  Future<String> readFrame(BurstFrame frame) {
    return _serialise(() async {
      final recognizer = _recognizer;

      final InputImage input;
      final nv21 = frame.nv21;

      if (nv21 != null) {
        input = InputImage.fromBytes(
          bytes: nv21,
          metadata: InputImageMetadata(
            size: Size(frame.width.toDouble(), frame.height.toDouble()),
            rotation: _rotation(frame.rotation),
            format: InputImageFormat.nv21,
            bytesPerRow: frame.width,
          ),
        );
      } else if (frame.path != null) {
        input = InputImage.fromFilePath(frame.path!);
      } else {
        return '';
      }

      try {
        final result = await recognizer.processImage(input);
        return result.text;
      } catch (_) {
        // A single bad frame must not kill the screen. The caller speaks
        // "I could not read any text" instead.
        return '';
      }
    });
  }

  /// Reads text directly from a live NV21 camera frame, without touching disk.
  ///
  /// [rotation] is the clockwise rotation needed to make the image upright,
  /// in degrees (0, 90, 180 or 270). ML Kit applies it before recognition, so
  /// the returned block boxes are already in upright coordinates.
  Future<OcrRead> readLiveFrame({
    required Uint8List nv21,
    required int width,
    required int height,
    required int rotation,
  }) {
    return _serialise(() async {
      if (nv21.isEmpty || width <= 0 || height <= 0) {
        return const OcrRead(text: '', blocks: <TextBlock>[]);
      }

      try {
        final input = InputImage.fromBytes(
          bytes: nv21,
          metadata: InputImageMetadata(
            size: Size(width.toDouble(), height.toDouble()),
            rotation: _rotation(rotation),
            format: InputImageFormat.nv21,
            bytesPerRow: width,
          ),
        );

        final result = await _recognizer.processImage(input);
        return OcrRead(
          text: result.text,
          blocks: result.blocks,
          confidence: _meanConfidence(result.blocks),
        );
      } catch (_) {
        return const OcrRead(text: '', blocks: <TextBlock>[]);
      }
    });
  }

  Future<void> dispose() async {
    await _tail;
    await _latin?.close();
    _latin = null;
  }
}

/// Length-weighted mean of the per-line confidences ML Kit reports.
///
/// Lines are used rather than elements because a line's confidence already
/// reflects its elements, and weighting by characters keeps a single long line
/// from being outvoted by several two-word fragments.
double? _meanConfidence(List<TextBlock> blocks) {
  var weighted = 0.0;
  var weight = 0;

  for (final block in blocks) {
    for (final line in block.lines) {
      final confidence = line.confidence;
      if (confidence == null) continue;
      final length = line.text.trim().length;
      if (length == 0) continue;
      weighted += confidence * length;
      weight += length;
    }
  }

  if (weight == 0) return null;
  return weighted / weight;
}

InputImageRotation _rotation(int degrees) {
  return switch (degrees % 360) {
    90 => InputImageRotation.rotation90deg,
    180 => InputImageRotation.rotation180deg,
    270 => InputImageRotation.rotation270deg,
    _ => InputImageRotation.rotation0deg,
  };
}

/// Cleans recognised text so it sounds right when spoken.
///
/// OCR output is laid out in visual lines. Spoken aloud, those line breaks
/// become odd pauses mid-sentence, and hyphenated words get split in two.
String speakable(String raw) {
  var text = raw.replaceAll(RegExp(r'-\s*\n'), '');
  text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
  text = text.replaceAll(RegExp(r'\s*\n\s*'), ' ');
  return text.trim();
}
