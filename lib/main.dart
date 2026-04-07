import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app/app.dart';
import 'core/persistence/prefs_service.dart';
import 'core/platform/overlay_bridge.dart';
import 'core/routing/deep_link_gate.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/desktop/desktop_pairing_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/push_messaging_service.dart';
import 'firebase_options.dart';
import 'web_app/web_app.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    OverlayBridge.ensureInitialized();
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e, st) {
    debugPrint('Firebase.initializeApp failed: $e');
    debugPrintStack(stackTrace: st);
  }

  try {
    await DesktopPairingService.initializeSupabase();
  } catch (e, st) {
    debugPrint('DesktopPairingService.initializeSupabase failed: $e');
    debugPrintStack(stackTrace: st);
  }

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  if (!kIsWeb) {
    try {
      FirebaseFirestore.instance.settings =
          const Settings(persistenceEnabled: false);
    } catch (_) {}
  }

  if (!kIsWeb) {
    try {
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);

      FlutterError.onError = (details) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e, st) {
      debugPrint('Crashlytics setup failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  runZonedGuarded(() async {
    final prefs = await PreferencesService.create();

    await ConnectivityService.instance.initialize();

    if (!kIsWeb) {
      try {
        await NotificationService().init();
      } catch (e, st) {
        await FirebaseCrashlytics.instance.recordError(e, st, fatal: false);
      }

      try {
        await PushMessagingService.instance.init();
      } catch (e, st) {
        await FirebaseCrashlytics.instance.recordError(e, st, fatal: false);
      }
    }

    final Widget app = kIsWeb
        ? const _ResponsiveWebEntry()
        : DeepLinkGate(
            child: const EleagueHubApp(),
          );

    runApp(
      ProviderScope(
        overrides: [
          prefsServiceProvider.overrideWithValue(prefs),
        ],
        child: app,
      ),
    );
  }, (error, stack) async {
    if (!kIsWeb) {
      try {
        await FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      } catch (_) {}
    } else {
      debugPrint('Uncaught zone error: $error');
      debugPrintStack(stackTrace: stack);
    }
  });
}

class _ResponsiveWebEntry extends StatelessWidget {
  const _ResponsiveWebEntry();

  static const double _desktopWebMinWidth = 760;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width >= _desktopWebMinWidth) {
          return const EleagueHubWebApp();
        }

        return DeepLinkGate(
          child: const EleagueHubApp(),
        );
      },
    );
  }
}
