import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local settings for object announcements and one-time mode hints.
class ObjectPreferences {
  ObjectPreferences._();

  static final instance = ObjectPreferences._();
  bool automatic = false;
  final _introduced = <String>{};
  File? _file;
  Future<void> _pending = Future.value();

  Future<void> load() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = _file = File('${directory.path}/cue_modes.json');
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map) return;
      automatic = data['automatic'] == true;
      final hints = data['introduced'];
      if (hints is List) _introduced.addAll(hints.whereType<String>());
    } catch (_) {
      // Settings are optional when storage is unavailable.
    }
  }

  bool firstVisit(String mode) {
    if (!_introduced.add(mode)) return false;
    _save();
    return true;
  }

  void setAutomatic(bool enabled) {
    automatic = enabled;
    _save();
  }

  void _save() {
    final json = jsonEncode({
      'automatic': automatic,
      'introduced': _introduced.toList(),
    });
    _pending = _pending.then((_) async {
      try {
        await _file?.writeAsString(json, flush: true);
      } catch (_) {
        // The in-memory choice remains valid for this session.
      }
    });
  }
}
