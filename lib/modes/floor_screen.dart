import 'package:flutter/material.dart';

import '../core/audio_bus.dart';
import '../widgets/big_button.dart';

/// Mode 3 - Floor.
/// Day 6: camera aimed down, torch during capture, small-object result.
class FloorScreen extends StatefulWidget {
  const FloorScreen({super.key});

  @override
  State<FloorScreen> createState() => _FloorScreenState();
}

class _FloorScreenState extends State<FloorScreen> {
  @override
  void initState() {
    super.initState();
    AudioBus.instance.say(
      'Floor mode. Hold the phone pointing down, then press Scan.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Floor')),
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
                label: 'Scan',
                icon: Icons.camera_alt,
                onPressed: () =>
                    AudioBus.instance.say('Floor mode is not built yet.'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
