import 'package:cue/live/screen_status.dart';
import 'package:flutter_test/flutter_test.dart';

ScreenStatus _updating([int? percent]) =>
    (activity: ScreenActivity.updating, percent: percent, prompt: null);

void main() {
  group('recognising screen status in Text mode', () {
    test('reads a short loading message', () {
      const loading = (
        activity: ScreenActivity.loading,
        percent: null,
        prompt: null,
      );
      expect(analyseScreenStatus('Loading…'), loading);
      expect(analyseScreenStatus('Loading... Please wait.'), loading);
    });

    test('reads update progress on the same line or next to status text', () {
      expect(
        analyseScreenStatus('Working on updates 42% complete'),
        _updating(42),
      );
      expect(
        analyseScreenStatus(
          'Updates are underway.\nPlease keep your computer on.\n42% complete',
        ),
        _updating(42),
      );
      expect(
        screenStatusSpeech(_updating(42), hindi: false),
        'Updating, 42 percent.',
      );
    });

    test('reads Hindi status and Devanagari digits', () {
      final status = analyseScreenStatus('अपडेट हो रहा है।\n४२ प्रतिशत पूरा।');
      expect(status, _updating(42));
      expect(
        screenStatusSpeech(status!, hindi: true),
        'अपडेट हो रहा है, 42 प्रतिशत।',
      );
    });

    test('uses the actual phase when a restart is required or in progress', () {
      expect(
        analyseScreenStatus('Restart required')?.activity,
        ScreenActivity.restartRequired,
      );
      expect(
        analyseScreenStatus('Restarting…')?.activity,
        ScreenActivity.restarting,
      );
      expect(
        analyseScreenStatus('Please wait\nInstalling updates')?.activity,
        ScreenActivity.installing,
      );
      expect(
        analyseScreenStatus('Updates completed successfully.')?.activity,
        ScreenActivity.complete,
      );
    });

    test('leaves commands, percentages alone and prose to regular reading', () {
      for (final text in [
        'Check for updates',
        'Download and install',
        'Windows Update\nBattery 82%',
        '42% complete',
        'Loading\nA guide to how web pages load',
        'Updating your computer is an important part of maintenance.',
        List.filled(10, 'Please wait for the next step.').join('\n'),
        'Downloading 42%\nInstalling 19%',
        'Working on updates 42%\nWorking on updates 49%',
      ]) {
        expect(analyseScreenStatus(text), isNull, reason: text);
      }
    });

    test('reports the phase without an unrelated or invalid percentage', () {
      expect(
        analyseScreenStatus('Working on updates\nBattery 82%'),
        _updating(),
      );
      expect(analyseScreenStatus('Updating 103%'), _updating());
      expect(analyseScreenStatus('Updating 100%'), _updating(100));
      expect(
        analyseScreenStatus('Updating 10.5%\nPlease keep your computer on.'),
        isNull,
      );
    });

    test('preserves the keys and choices on a pre-boot prompt', () {
      const text = 'System setup\nPress F1 to continue or F2 to enter Setup';
      expect(analyseScreenStatus(text), isNull);
      final prompt = analyseScreenStatus(text, includeInputPrompts: true);
      expect(prompt?.activity, ScreenActivity.inputPrompt);
      expect(
        screenStatusSpeech(prompt!, hindi: false),
        'The screen says, Press F1 to continue or F2 to enter Setup.',
      );
      expect(
        analyseScreenStatus(
          'In this chapter you will press F1 to continue.',
          includeInputPrompts: true,
        ),
        isNull,
      );
    });
  });

  group('announcing screen status', () {
    final start = DateTime(2026);
    DateTime at(int seconds) => start.add(Duration(seconds: seconds));

    test('requires fresh agreement and keeps steady readings quiet', () {
      final tracker = ScreenStatusTracker();
      expect(tracker.observe(_updating(42), at(0)), isNull);
      expect(tracker.observe(_updating(42), at(0)), isNull);
      final confirmed = tracker.observe(_updating(42), at(1));
      expect(confirmed, _updating(42));
      tracker.markAnnounced(confirmed!, at(1));
      expect(tracker.observe(_updating(42), at(2)), isNull);
    });

    test('can speak the phase while the percentage is changing', () {
      final tracker = ScreenStatusTracker();
      expect(tracker.observe(_updating(41), at(0)), isNull);
      expect(tracker.observe(_updating(42), at(1)), _updating());
    });

    test('keeps small and quick changes quiet and reports a larger step', () {
      final tracker = ScreenStatusTracker()
        ..markAnnounced(_updating(42), at(0));
      for (final seconds in [1, 2, 5, 8, 9]) {
        expect(tracker.observe(_updating(47), at(seconds)), isNull);
      }
      expect(tracker.observe(_updating(52), at(10)), isNull);
      final confirmed = tracker.observe(_updating(52), at(11));
      expect(confirmed, _updating(52));
      tracker.markAnnounced(confirmed!, at(11));
      expect(tracker.observe(_updating(100), at(12)), isNull);
      expect(tracker.observe(_updating(100), at(13)), _updating(100));
    });

    test('replaces an earlier phase even within the progress cooldown', () {
      final tracker = ScreenStatusTracker()
        ..markAnnounced(_updating(42), at(0));
      const restarting = (
        activity: ScreenActivity.restarting,
        percent: null,
        prompt: null,
      );
      expect(tracker.observe(restarting, at(1)), isNull);
      expect(tracker.observe(restarting, at(2)), restarting);
    });

    test('a brief OCR miss keeps the last announcement quiet', () {
      final tracker = ScreenStatusTracker();
      tracker.observe(_updating(42), at(0));
      tracker.markAnnounced(tracker.observe(_updating(42), at(1))!, at(1));
      expect(tracker.observe(null, at(2)), isNull);
      expect(tracker.observe(_updating(42), at(3)), isNull);
      expect(tracker.observe(_updating(42), at(4)), isNull);
      expect(tracker.observe(_updating(42), at(14)), isNull);
      expect(tracker.observe(_updating(42), at(15)), _updating(42));
    });

    test('a key prompt has to agree before Cue speaks the key', () {
      final tracker = ScreenStatusTracker();
      final first = analyseScreenStatus(
        'Press F1 to continue',
        includeInputPrompts: true,
      );
      final next = analyseScreenStatus(
        'Press F2 to continue',
        includeInputPrompts: true,
      );
      expect(tracker.observe(first, at(0)), isNull);
      expect(tracker.observe(next, at(1)), isNull);
      expect(tracker.observe(next, at(2)), next);
    });
  });
}
