import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app/app.dart';
import 'core/app/sync_bootstrap.dart';
import 'core/persistence/prefs_service.dart';
import 'core/platform/overlay_bridge.dart';
import 'core/services/auth_bootstrap.dart';
import 'core/services/notification_service.dart';
import 'core/services/sync_queue_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Overlay actions from Android (bubble + notification) must be wired early.
  OverlayBridge.ensureInitialized();

  await Firebase.initializeApp();

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
    SyncQueueService.init(prefs);

    try {
      // Ensure we have a FirebaseAuth session before any Firestore reads/writes.
      await AuthBootstrap.syncCurrentUserToPrefs(
        prefs,
        autoSignInAnonymously: true,
      );

      final u = FirebaseAuth.instance.currentUser;
      // ignore: avoid_print
      print('main → auth uid=${u?.uid} anon=${u?.isAnonymous}');
    } catch (e) {
      // ignore: avoid_print
      print('AuthBootstrap sync failed (non-fatal): $e');
    }

    try {
      await NotificationService().init();
    } catch (e) {
      // ignore: avoid_print
      print('NotificationService init failed (non-fatal): $e');
    }

    try {
      await SyncBootstrap.init();
    } catch (e) {
      // ignore: avoid_print
      print('SyncBootstrap init failed (non-fatal): $e');
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
