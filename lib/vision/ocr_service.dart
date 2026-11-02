import 'dart:ui' show Size;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'burst.dart';

/// Turns a photo of text into words.
///
/// Runs entirely on the phone. No image is uploaded anywhere, which is what
/// the client asked for: "works with no signal".
class OcrService {
  OcrService._();

  static final OcrService instance = OcrService._();

  TextRecognizer? _latin;

  /// Returns the text found in [frame], or an empty string.
  Future<String> readFrame(BurstFrame frame) async {
    final recognizer =
        _latin ??= TextRecognizer(script: TextRecognitionScript.latin);

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
  }

  Future<void> dispose() async {
    await _latin?.close();
    _latin = null;
  }
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
