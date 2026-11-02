import 'package:flutter/material.dart';

import '../core/audio_bus.dart';
import '../widgets/big_button.dart';

/// Mode 4 - Walk.
/// Day 6: static map, spoken instructions, obstacle warning placeholder.
class WalkScreen extends StatefulWidget {
  const WalkScreen({super.key});

  @override
  State<WalkScreen> createState() => _WalkScreenState();
}

class _WalkScreenState extends State<WalkScreen> {
  bool _walking = false;

  @override
  void initState() {
    super.initState();
    AudioBus.instance.say(
      'Walk mode. Press Start when you are ready to move.',
    );
  }

  void _toggle() {
    setState(() => _walking = !_walking);
    AudioBus.instance.say(
      _walking ? 'Walking. Path is clear.' : 'Stopped.',
      priority: SpeechPriority.navigation,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Walk')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    _walking ? 'Walking...' : 'Stopped',
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
              ),
              BigButton(
                label: _walking ? 'Stop' : 'Start',
                icon: _walking ? Icons.stop : Icons.play_arrow,
                onPressed: _toggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
