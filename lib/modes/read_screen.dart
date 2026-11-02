import 'package:flutter/material.dart';

import '../core/audio_bus.dart';
import '../widgets/big_button.dart';

/// Mode 1 - Read.
/// Day 4: replace the placeholder with camera + ML Kit text recognition.
class ReadScreen extends StatefulWidget {
  const ReadScreen({super.key});

  @override
  State<ReadScreen> createState() => _ReadScreenState();
}

class _ReadScreenState extends State<ReadScreen> {
  @override
  void initState() {
    super.initState();
    AudioBus.instance.say(
      'Read mode. Point the phone at the page, then press Capture.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Read')),
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
                    AudioBus.instance.say('Read mode is not built yet.'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
