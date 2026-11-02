import 'package:flutter/material.dart';

import '../core/audio_bus.dart';
import '../widgets/big_button.dart';

/// Mode 2 - Identify.
/// Day 5: camera + ML Kit image labelling + colour + rough distance.
class IdentifyScreen extends StatefulWidget {
  const IdentifyScreen({super.key});

  @override
  State<IdentifyScreen> createState() => _IdentifyScreenState();
}

class _IdentifyScreenState extends State<IdentifyScreen> {
  @override
  void initState() {
    super.initState();
    AudioBus.instance.say(
      'Identify mode. Point the phone at the object, then press Capture.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Identify')),
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
                label: 'Capture',
                icon: Icons.camera_alt,
                onPressed: () =>
                    AudioBus.instance.say('Identify mode is not built yet.'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
