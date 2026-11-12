import 'dart:async';

import 'package:flutter/material.dart';

import '../core/audio_bus.dart';
import '../core/cue_language.dart';
import '../core/tts_service.dart';
import '../widgets/big_button.dart';

/// Settings.
/// Provides controls for speech rate, language, voice test, and feedback toggles.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _haptics = true;
  bool _keepScreenOff = true;
  double _speechRate = TtsService.defaultRate;

  @override
  void initState() {
    super.initState();
    _speechRate = TtsService.instance.rate;
    unawaited(AudioBus.instance.say('Settings.'));
  }

  Future<void> _adjustRate({required bool faster}) async {
    final changed = faster
        ? await TtsService.instance.faster()
        : await TtsService.instance.slower();

    if (mounted && changed) {
      setState(() => _speechRate = TtsService.instance.rate);
    }
  }

  Future<void> _setLanguage(CueLanguage language) async {
    await LanguageService.instance.set(language);
    await TtsService.instance.setLanguage(language);
    if (mounted) setState(() {});
    final isHindi = language.isHindi;
    unawaited(
      AudioBus.instance.say(
        isHindi ? 'हिंदी चुनी गई।' : 'English selected.',
      ),
    );
  }

  void _testVoice() {
    final isHindi = LanguageService.instance.language.value.isHindi;
    final text = isHindi
        ? 'क्यू की आवाज़ स्पष्ट और तैयार है।'
        : 'Cue voice is clear, articulate, and ready.';
    unawaited(AudioBus.instance.say(text));
  }

  @override
  Widget build(BuildContext context) {
    final currentLang = LanguageService.instance.language.value;
    final ratePercent = ((_speechRate / 0.50) * 100).round();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Voice & Speech',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              title: const Text(
                'Speech Speed',
                style: TextStyle(fontSize: 18),
              ),
              subtitle: Text(
                '$ratePercent% of normal pace',
                style: const TextStyle(fontSize: 15, color: Colors.grey),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Slower',
                    onPressed: () => _adjustRate(faster: false),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Faster',
                    onPressed: () => _adjustRate(faster: true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              title: const Text(
                'Reading Language',
                style: TextStyle(fontSize: 18),
              ),
              trailing: SegmentedButton<CueLanguage>(
                segments: const [
                  ButtonSegment(
                    value: CueLanguage.english,
                    label: Text('English'),
                  ),
                  ButtonSegment(
                    value: CueLanguage.hindi,
                    label: Text('हिंदी'),
                  ),
                ],
                selected: {currentLang},
                onSelectionChanged: (selected) {
                  if (selected.isNotEmpty) {
                    _setLanguage(selected.first);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            BigButton(
              label: 'Test voice clarity',
              icon: Icons.volume_up,
              onPressed: _testVoice,
            ),
            const Divider(height: 32),
            const Text(
              'Hardware & Feedback',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text(
                'Vibration feedback',
                style: TextStyle(fontSize: 18),
              ),
              value: _haptics,
              onChanged: (v) => setState(() => _haptics = v),
            ),
            SwitchListTile(
              title: const Text(
                'Keep screen off',
                style: TextStyle(fontSize: 18),
              ),
              subtitle: const Text('Saves battery during live tracking'),
              value: _keepScreenOff,
              onChanged: (v) => setState(() => _keepScreenOff = v),
            ),
          ],
        ),
      ),
    );
  }
}
