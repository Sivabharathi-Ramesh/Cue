import 'package:flutter/material.dart';

import '../core/audio_bus.dart';
import '../widgets/big_button.dart';

/// Mode 5 - Currency.
/// Day 6: reuse the Identify pipeline with a note-specific result.
class CurrencyScreen extends StatefulWidget {
  const CurrencyScreen({super.key});

  @override
  State<CurrencyScreen> createState() => _CurrencyScreenState();
}

class _CurrencyScreenState extends State<CurrencyScreen> {
  @override
  void initState() {
    super.initState();
    AudioBus.instance.say(
      'Currency mode. Hold the note flat, then press Check.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Currency')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Expanded(
                child: Center(
                  child: Text(
                    'Camera preview goes here',
                    style: TextStyle(fontSize: 20),
                  ),
                ),
              ),
              BigButton(
                label: 'Check',
                icon: Icons.camera_alt,
                onPressed: () =>
                    AudioBus.instance.say('Currency mode is not built yet.'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
