import 'package:flutter/material.dart';

import '../core/audio_bus.dart';
import '../widgets/big_button.dart';

/// Settings.
/// Day 7: speech rate, haptics on/off, keep-screen-off, battery status.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _haptics = true;
  bool _keepScreenOff = true;

  @override
  void initState() {
    super.initState();
    AudioBus.instance.say('Settings.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              title: const Text('Vibration feedback', style: TextStyle(fontSize: 20)),
              value: _haptics,
              onChanged: (v) => setState(() => _haptics = v),
            ),
            SwitchListTile(
              title: const Text('Keep screen off', style: TextStyle(fontSize: 20)),
              subtitle: const Text('Saves battery in walk mode'),
              value: _keepScreenOff,
              onChanged: (v) => setState(() => _keepScreenOff = v),
            ),
            const SizedBox(height: 16),
            BigButton(
              label: 'Test voice',
              icon: Icons.volume_up,
              onPressed: () => AudioBus.instance.say(
                'This is the Cue voice at the current speed.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
