import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A one-time flag for the spoken voice-command introduction.
///
/// The first time Cue starts it explains how to talk to it. After that the
/// hint is dropped, so a regular user is not told the same thing at every
/// launch. The flag is a tiny file in the app's support folder; if anything
/// fails, Cue simply skips the introduction rather than nagging.
Future<bool> voiceIntroNeeded() async {
  try {
    final file = await _file();
    return !await file.exists();
  } catch (_) {
    return false;
  }
}

Future<void> markVoiceIntroSeen() async {
  try {
    final file = await _file();
    await file.writeAsString('seen');
  } catch (_) {
    // A missing flag only means the hint may be heard again.
  }
}

Future<File> _file() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/cue_voice_intro.txt');
}
