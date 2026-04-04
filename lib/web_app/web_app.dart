import 'package:flutter/material.dart';

class EleagueHubWebApp extends StatelessWidget {
  const EleagueHubWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0B141A),
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            child: const Text(
              'Web app smoke test OK',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
