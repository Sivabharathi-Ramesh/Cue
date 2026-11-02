import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Turns a photo of text into words.
///
/// Runs entirely on the phone. No image is uploaded anywhere, which is what
/// the client asked for: "works with no signal".
class OcrService {
  OcrService._();

  static final OcrService instance = OcrService._();

  TextRecognizer? _latin;

  /// Returns the text found in the image, or an empty string.
  Future<String> readText(String path) async {
    final recognizer =
        _latin ??= TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final input = InputImage.fromFilePath(path);
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
