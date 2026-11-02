import 'package:flutter/material.dart';

import '../core/audio_bus.dart';
import '../widgets/big_button.dart';
import 'currency_screen.dart';
import 'floor_screen.dart';
import 'identify_screen.dart';
import 'read_screen.dart';
import 'settings_screen.dart';
import 'walk_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    AudioBus.instance.say('Cue ready. Choose a mode.');
  }

  void _open(Widget screen) {
    AudioBus.instance.stop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cue'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          children: [
            BigButton(
              label: 'Read',
              icon: Icons.menu_book,
              semanticHint: 'Reads a page aloud, word by word',
              onPressed: () => _open(const ReadScreen()),
            ),
            BigButton(
              label: 'Identify',
              icon: Icons.search,
              semanticHint: 'Names an object, its colour and distance',
              onPressed: () => _open(const IdentifyScreen()),
            ),
            BigButton(
              label: 'Floor',
              icon: Icons.south,
              semanticHint: 'Finds small objects that have fallen',
              onPressed: () => _open(const FloorScreen()),
            ),
            BigButton(
              label: 'Walk',
              icon: Icons.directions_walk,
              semanticHint: 'Warns about obstacles ahead',
              onPressed: () => _open(const WalkScreen()),
            ),
            BigButton(
              label: 'Currency',
              icon: Icons.payments,
              semanticHint: 'Identifies a bank note',
              onPressed: () => _open(const CurrencyScreen()),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => _open(const SettingsScreen()),
              child: const Text('Settings', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
