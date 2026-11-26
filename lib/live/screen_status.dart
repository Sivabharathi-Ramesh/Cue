/// A status inferred from the wording of a short OCR reading.
enum ScreenActivity {
  waiting('Please wait', 'कृपया प्रतीक्षा करें'),
  loading('Loading', 'लोड हो रहा है'),
  preparing('Getting things ready', 'तैयारी हो रही है'),
  checking('Checking for updates', 'अपडेट की जाँच हो रही है'),
  downloading('Downloading', 'डाउनलोड हो रहा है'),
  installing('Installing', 'इंस्टॉल हो रहा है'),
  updating('Updating', 'अपडेट हो रहा है'),
  restarting('Restarting', 'कंप्यूटर फिर से शुरू हो रहा है'),
  restartRequired('Restart required', 'कंप्यूटर फिर से शुरू करना होगा'),
  complete('Updates complete', 'अपडेट पूरे हो गए हैं'),
  failed('Update failed', 'अपडेट पूरा नहीं हो सका'),
  reverting('Undoing changes', 'बदलाव वापस किए जा रहे हैं'),
  inputPrompt('Screen prompt', 'स्क्रीन पर निर्देश');

  const ScreenActivity(this.english, this.hindi);
  final String english;
  final String hindi;
}

typedef ScreenStatus = ({
  ScreenActivity activity,
  int? percent,
  String? prompt,
});

String screenStatusSpeech(ScreenStatus status, {required bool hindi}) {
  if (status.prompt case final prompt?) {
    return hindi ? 'स्क्रीन पर लिखा है। $prompt' : 'The screen says, $prompt';
  }
  final activity = hindi ? status.activity.hindi : status.activity.english;
  final percent = status.percent;
  if (percent == null) return hindi ? '$activity।' : '$activity.';
  return hindi
      ? '$activity, $percent प्रतिशत।'
      : '$activity, $percent percent.';
}

final _activities = <ScreenActivity, RegExp>{
  ScreenActivity.waiting: RegExp(
    r'^(?:please wait|just a moment|कृपया प्रतीक्षा करें|कृपया इंतज़ार करें)$',
  ),
  ScreenActivity.loading: RegExp(
    r'^(?:loading(?: (?:windows|(?:your )?(?:settings|profile|page|files)))?|लोड हो रहा है)$',
  ),
  ScreenActivity.preparing: RegExp(
    r'^(?:getting (?:windows|things) ready|preparing (?:windows|updates|to update)|तैयारी हो रही है)$',
  ),
  ScreenActivity.checking: RegExp(
    r'^(?:checking for updates|अपडेट (?:की |के लिए )जाँच हो रही है)$',
  ),
  ScreenActivity.downloading: RegExp(
    r'^(?:downloading(?: (?:an? )?updates?)?|(?:अपडेट )?डाउनलोड हो रहा है)$',
  ),
  ScreenActivity.installing: RegExp(
    r'^(?:installing(?: (?:an? )?updates?)?|(?:अपडेट )?इंस्टॉल हो रहा है)$',
  ),
  ScreenActivity.updating: RegExp(
    r'^(?:updating(?: (?:windows|your computer|your device))?|working on updates|updates are underway|अपडेट हो रहा है|अपडेट किए जा रहे हैं)$',
  ),
  ScreenActivity.restarting: RegExp(
    r'^(?:restarting|rebooting|(?:कंप्यूटर )?फिर से शुरू हो रहा है|रीस्टार्ट हो रहा है)$',
  ),
  ScreenActivity.restartRequired: RegExp(
    r'^(?:restart required|restart needed|रीस्टार्ट करना होगा)$',
  ),
  ScreenActivity.complete: RegExp(
    r'^(?:updates? (?:are )?(?:completed?(?: successfully)?|installed successfully)|अपडेट (?:पूरा हो गया है|पूरे हो गए हैं))$',
  ),
  ScreenActivity.failed: RegExp(
    r"^(?:updates? failed|(?:we )?couldn['’]t complete (?:the )?updates|अपडेट पूरा नहीं हो सका)$",
  ),
  ScreenActivity.reverting: RegExp(
    r'^(?:undoing changes(?: made to your computer)?|reverting changes|बदलाव वापस किए जा रहे हैं)$',
  ),
};

final _progress = RegExp(
  r'([0-9]{1,3})\s*(?:[%％]|\bpercent\b|प्रतिशत)\)?(?:\s+(?:complete|completed|पूरा|पूर्ण))?$',
);
final _lastPunctuation = RegExp(r'[\s.…:(),!;।–—-]+$');
final _waitingSuffix = RegExp(r'[,.…!]\s*please wait$');
final _statusNote = RegExp(
  r"^(?:please wait|(?:please )?keep your (?:computer|pc|device) on|"
  r"(?:please )?(?:do not|don['’]t) turn off your (?:computer|pc|device)|"
  r"this (?:may|will) take (?:a while|a few minutes)|"
  r"कृपया प्रतीक्षा करें|कृपया कंप्यूटर बंद न करें)$",
);
final _continuesNumber = RegExp(r'[0-9.]$');
final _spaces = RegExp(r'\s+');
final _hindiDigits = RegExp(r'[०-९]');
final _keyPrompt = RegExp(
  r'^press\s+(?:the\s+)?<?'
  r'(?:f(?:1[0-2]|[1-9])|enter|return|esc(?:ape)?|del(?:ete)?|any key|space(?:bar)?)'
  r'>?(?:\s+key)?'
  r'(?:\s+to\s+(?:continue|proceed|resume|enter|run|open|start|boot|access|retry|select|exit|cancel)\b.*)?'
  r'[.!…]*$',
  caseSensitive: false,
);
final _promptEnd = RegExp(r'[.!…।]+$');

/// Recognises status lines and their adjacent progress on short panels.
/// Ordinary paragraphs and conflicting updates fall through to text reading.
ScreenStatus? analyseScreenStatus(
  String text, {
  bool includeInputPrompts = false,
}) {
  if (includeInputPrompts) {
    final prompts = text
        .split('\n')
        .map((line) => line.trim().replaceAll(_spaces, ' '))
        .where((line) => line.length <= 140 && _keyPrompt.hasMatch(line))
        .map((line) => line.replaceAll(_promptEnd, ''))
        .take(2)
        .toList();
    if (prompts.isNotEmpty) {
      return (
        activity: ScreenActivity.inputPrompt,
        percent: null,
        prompt: '${prompts.join('. ')}.',
      );
    }
  }
  if (text.trim().length > 280) return null;
  final lines = text
      .split('\n')
      .map(_cleanLine)
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.length > 8 || lines.any((line) => line.split(' ').length > 16)) {
    return null;
  }

  final statuses = <ScreenActivity, int?>{};
  for (var i = 0; i < lines.length; i++) {
    final (phrase, inlinePercent) = _splitProgress(lines[i]);
    final activity = _activityFor(phrase);
    if (activity == null) continue;

    var percent = inlinePercent;
    if (percent == null) {
      var next = i + 1;
      while (next < lines.length && _statusNote.hasMatch(lines[next])) {
        next++;
      }
      if (next < lines.length) {
        final (prefix, nextPercent) = _splitProgress(lines[next]);
        if (prefix.isEmpty) percent = nextPercent;
      }
    }
    // A one-word heading above prose is common in documents.
    if (percent == null &&
        lines[i] == phrase &&
        !phrase.contains(' ') &&
        lines.any((line) => line != phrase && !_statusNote.hasMatch(line))) {
      continue;
    }
    final previous = statuses[activity];
    if (previous != null && percent != null && previous != percent) return null;
    statuses[activity] = percent ?? previous;
  }
  // A status panel can include both its main message and "Please wait".
  if (statuses.length > 1) statuses.remove(ScreenActivity.waiting);
  if (statuses.length != 1) return null;
  final status = statuses.entries.single;
  return (activity: status.key, percent: status.value, prompt: null);
}

String _cleanLine(String line) => line
    .toLowerCase()
    .replaceAll(_spaces, ' ')
    .replaceAllMapped(
      _hindiDigits,
      (digit) => (digit[0]!.codeUnitAt(0) - '०'.codeUnitAt(0)).toString(),
    )
    .trim()
    .replaceAll(_lastPunctuation, '')
    .replaceFirst(_waitingSuffix, '')
    .replaceAll(_lastPunctuation, '');

(String, int?) _splitProgress(String line) {
  final match = _progress.firstMatch(line);
  if (match == null) return (line, null);
  final prefix = line.substring(0, match.start);
  // A fraction or longer number must not be read as its final digits.
  if (_continuesNumber.hasMatch(prefix)) {
    return (line, null);
  }
  final percent = int.parse(match[1]!);
  return (
    prefix.replaceAll(_lastPunctuation, ''),
    percent <= 100 ? percent : null,
  );
}

ScreenActivity? _activityFor(String line) {
  for (final entry in _activities.entries) {
    if (entry.value.hasMatch(line)) return entry.key;
  }
  return null;
}

/// Confirms a status on fresh frames and spaces progress announcements.
class ScreenStatusTracker {
  static const _confirmationWindow = Duration(seconds: 4);
  static const _returnWindow = Duration(seconds: 8);
  static const _progressInterval = Duration(seconds: 8);
  static const _progressStep = 10;

  ScreenStatus? _previous;
  DateTime? _lastSeenAt;
  ScreenStatus? _announced;
  DateTime? _announcedAt;

  bool get hasCandidate => _previous != null;

  ScreenStatus? observe(ScreenStatus? status, DateTime now) {
    final previous = _previous;
    final lastSeen = _lastSeenAt;
    final elapsed = lastSeen == null ? null : now.difference(lastSeen);
    if (elapsed != null && elapsed >= _returnWindow) reset();
    _previous = status;
    if (status == null) return null;
    _lastSeenAt = now;

    if (previous?.activity != status.activity ||
        previous?.prompt?.toLowerCase() != status.prompt?.toLowerCase() ||
        elapsed == null ||
        elapsed <= Duration.zero ||
        elapsed > _confirmationWindow) {
      return null;
    }

    // The phase can be stable while the number on screen is still changing.
    final percent = previous!.percent == status.percent ? status.percent : null;
    final confirmed = (
      activity: status.activity,
      percent: percent,
      prompt: status.prompt,
    );
    final announced = _announced;
    if (announced?.activity != status.activity ||
        announced?.prompt?.toLowerCase() != status.prompt?.toLowerCase()) {
      return confirmed;
    }
    if (percent == null) return null;

    final lastPercent = announced!.percent;
    if (percent == 100 && lastPercent != 100) return confirmed;
    if (now.difference(_announcedAt!) < _progressInterval) return null;
    return lastPercent == null || percent >= lastPercent + _progressStep
        ? confirmed
        : null;
  }

  void markAnnounced(ScreenStatus status, DateTime now) {
    _announced = status;
    _announcedAt = now;
  }

  void reset() {
    _previous = null;
    _lastSeenAt = null;
    _announced = null;
    _announcedAt = null;
  }
}
