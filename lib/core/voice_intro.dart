import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Version of the spoken introduction, so existing users hear new shortcuts.
const _introVersion = 'gesture-help-2';

/// Plays the introduction once per version.
Future<bool> voiceIntroNeeded() async {
  try {
    final file = await _file();
    return !await file.exists() || await file.readAsString() != _introVersion;
  } catch (_) {
    return false;
  }
}

Future<void> markVoiceIntroSeen() async {
  try {
    final file = await _file();
    await file.writeAsString(_introVersion);
  } catch (_) {
    // A missing flag only means the hint may be heard again.
  }
}

Future<File> _file() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/cue_voice_intro.txt');
}
