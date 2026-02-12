import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app/app.dart';
import 'core/persistence/prefs_service.dart';
import 'core/platform/overlay_bridge.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Overlay actions from Android (bubble + notification) must be wired early.
  OverlayBridge.ensureInitialized();

  await Firebase.initializeApp();

  // ONLINE-ONLY: disable Firestore local persistence/caching.
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);

  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);

  FlutterError.onError = (details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  runZonedGuarded(() async {
    final prefs = await PreferencesService.create();

    // Connectivity is used only for UX (e.g., offline banner) and fail-fast decisions.
    await ConnectivityService.instance.initialize();

    try {
      await NotificationService().init();
    } catch (e, st) {
      // Non-fatal: notifications are optional.
      await FirebaseCrashlytics.instance.recordError(e, st, fatal: false);
    }

    runApp(
      ProviderScope(
        overrides: [
          prefsServiceProvider.overrideWithValue(prefs),
        ],
        child: const EleagueHubApp(),
      ),
    );
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}
