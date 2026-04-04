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

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  OverlayBridge.ensureInitialized();

  await Firebase.initializeApp();
  await DesktopPairingService.initializeSupabase();

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  FirebaseFirestore.instance.settings =
      const Settings(persistenceEnabled: false);

  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(!kDebugMode);

  FlutterError.onError = (details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  runZonedGuarded(() async {
    final prefs = await PreferencesService.create();

    await ConnectivityService.instance.initialize();

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

    runApp(
      ProviderScope(
        overrides: [
          prefsServiceProvider.overrideWithValue(prefs),
        ],
        child: DeepLinkGate(
          child: const EleagueHubApp(),
        ),
      ),
    );
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}
