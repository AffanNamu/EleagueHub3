import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';

import 'core/app/app.dart';
import 'core/app/sync_bootstrap.dart';
import 'core/persistence/prefs_service.dart';
import 'core/services/auth_bootstrap.dart';
import 'core/services/notification_service.dart';
import 'core/services/sync_queue_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/locale/locale_controller.dart';
import 'core/widgets/offline_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Firebase
    await Firebase.initializeApp();

    // Local prefs
    final prefs = await PreferencesService.create();

    // Queue
    SyncQueueService.init(prefs);

    // Auth (anonymous)
    await AuthBootstrap.ensureSignedIn(prefs);

    // Notifications
    await NotificationService().init();

    // Connectivity + sync
    await SyncBootstrap.init();

    runApp(
      ProviderScope(
        overrides: [
          prefsServiceProvider.overrideWithValue(prefs),
        ],
        child: const AppRoot(),
      ),
    );
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Fatal Start Error: $e',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      ),
    );
  }
}

class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider).mode;
    final localeState = ref.watch(localeControllerProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'eSportlyic',
      themeMode: themeMode,
      theme: AppTheme.skyTheme(),
      darkTheme: AppTheme.navyTheme(),
      locale: localeState.locale,
      supportedLocales: LocaleController.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            ValueListenableBuilder<bool>(
              valueListenable: ConnectivityService.instance.isConnected,
              builder: (context, online, _) {
                return online ? const SizedBox.shrink() : const OfflineBanner();
              },
            ),
          ],
        );
      },
      home: const EleagueHubApp(),
    );
  }
}
