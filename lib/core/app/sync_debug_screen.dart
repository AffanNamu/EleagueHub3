import 'package:flutter/material.dart';

/// NOTE:
/// Firebase testing / sync debug UI has been removed from the app.
/// This screen is kept only as a harmless stub to avoid any accidental
/// build breaks if an old reference exists somewhere.
@Deprecated('Debug tools removed from app UI')
class SyncDebugScreen extends StatelessWidget {
  const SyncDebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug Tools')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Debug tools were removed from this build.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
