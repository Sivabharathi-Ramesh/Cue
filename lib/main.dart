import 'package:flutter/material.dart';

import 'live/live_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CueApp());
}

class CueApp extends StatelessWidget {
  const CueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cue',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF1A237E),
        scaffoldBackgroundColor: Colors.black,
      ),
      // FR-01: straight into the live camera. There is no home screen and no
      // mode menu.
      home: const LiveScreen(),
    );
  }
}
