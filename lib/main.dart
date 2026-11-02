import 'package:flutter/material.dart';

import 'modes/home_screen.dart';

void main() {
  runApp(const CueApp());
}

class CueApp extends StatelessWidget {
  const CueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cue',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1A237E),
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
      ),
      home: const HomeScreen(),
    );
  }
}
