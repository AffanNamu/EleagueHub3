import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import 'presentation/web_pairing_screen.dart';

class EleagueHubWebApp extends ConsumerWidget {
  const EleagueHubWebApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider).mode;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'eSportlyic Web',
      themeMode: themeMode,
      theme: AppTheme.skyTheme(),
      darkTheme: AppTheme.navyTheme(),
      initialRoute: '/',
      routes: {
        '/': (_) => const WebPairingScreen(),
        '/desktop': (_) => const WebPairingScreen(),
        '/web': (_) => const WebPairingScreen(),
      },
    );
  }
}
