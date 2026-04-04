import 'package:flutter/material.dart';

import 'presentation/web_pairing_screen.dart';

class EleagueHubWebApp extends StatelessWidget {
  const EleagueHubWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF25D366),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF25D366),
      ),
      home: const WebPairingScreen(),
    );
  }
}
