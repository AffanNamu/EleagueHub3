import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app/app.dart';
import 'core/persistence/prefs_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/locale/locale_controller.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/sync_queue_service.dart';
import 'core/widgets/offline_banner.dart';

Future<void> main() async {
  // Initialize Flutter engine
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Load persisted preferences
    final prefs = await PreferencesService.create();

    // Initialize Services
    ConnectivityService.instance.initialize();
    SyncQueueService.init(prefs); // Initialize Sync Queue with prefs
    await NotificationService().init();

    // Setup Auto-Sync listener when coming back online
    ConnectivityService.instance.isConnected.addListener(() {
      if (ConnectivityService.instance.isConnected.value) {
        // Trigger background sync when online
        // SyncQueueService.instance.syncAll(); 
      }
    });

    runApp(
      ProviderScope(
        overrides: [
          prefsServiceProvider.overrideWithValue(prefs),
        ],
        child: const AppRoot(),
      ),
    );
  } catch (e) {
    // Fallback in case of startup error
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'Fatal Start Error: $e',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ),
    ));
  }
}

class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch theme and locale
    final themeMode = ref.watch(themeControllerProvider).mode;
    final localeState = ref.watch(localeControllerProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'eSportlyic',

      // =========================
      // THEME CONFIGURATION
      // =========================
      themeMode: themeMode,
      theme: AppTheme.skyTheme(),      // Sky (light) theme
      darkTheme: AppTheme.navyTheme(), // Navy (dark) theme

      // =========================
      // LOCALE CONFIGURATION
      // =========================
      locale: localeState.locale,
      supportedLocales: LocaleController.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // =========================
      // CONNECTIVITY WRAPPER
      // =========================
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            ValueListenableBuilder<bool>(
              valueListenable:
                  ConnectivityService.instance.isConnected,
              builder: (context, online, _) {
                return online
                    ? const SizedBox.shrink()
                    : const OfflineBanner();
              },
            ),
          ],
        );
      },

      // =========================
      // APP ENTRY
      // =========================
      home: const EleagueHubApp(),
    );
  }
}
