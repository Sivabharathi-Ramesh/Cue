import 'package:flutter/material.dart';

import 'core/cue_language.dart';
import 'live/live_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The saved language must be known before the first OCR warm-up and before
  // the first spoken sentence, otherwise a Hindi user hears an English intro.
  await LanguageService.instance.init();
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
