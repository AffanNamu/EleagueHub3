import 'package:flutter/material.dart';

class EleagueHubWebApp extends StatelessWidget {
  const EleagueHubWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: Container(
            color: Colors.red,
            child: const Center(
              child: Text(
                'WEB SMOKE TEST OK',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.yellow,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
