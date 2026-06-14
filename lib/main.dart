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
import 'core/services/push_messaging_service.dart';
import 'firebase_options.dart';
import 'web_app/web_app.dart';

import 'core/services/admob_initializer_stub.dart'
    if (dart.library.io) 'core/services/admob_initializer.dart' as _admob;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}
}

Future<void> main() async {
  // 1. Initialize Flutter Bindings
  try {
    WidgetsFlutterBinding.ensureInitialized();
  } catch (e) {
    debugPrint('WidgetsFlutterBinding error: $e');
  }

  if (!kIsWeb) {
    try {
      OverlayBridge.ensureInitialized();
    } catch (_) {}
  }

  // 2. Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e, st) {
    debugPrint('Firebase.initializeApp failed: $e');
    debugPrintStack(stackTrace: st);
  }

  // 3. Initialize Supabase
  try {
    await DesktopPairingService.initializeSupabase();
  } catch (e, st) {
    debugPrint('DesktopPairingService.initializeSupabase failed: $e');
    debugPrintStack(stackTrace: st);
  }

  // 4. Initialize Google Mobile Ads (Android / iOS only)
  if (!kIsWeb) {
    try {
      await _admob.initializeMobileAds();
    } catch (e, st) {
      debugPrint('MobileAds.initialize failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  // 5. Mobile-only configurations
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    try {
      FirebaseFirestore.instance.settings =
          const Settings(persistenceEnabled: false);
    } catch (_) {}

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

  // 6. Run the App inside a guarded zone
  runZonedGuarded(() async {
    try {
      final prefs = await PreferencesService.create();

      try {
        await ConnectivityService.instance.initialize();
      } catch (e) {
        debugPrint('Connectivity init bypassed (safe on web): $e');
      }

      if (!kIsWeb) {
        // ─────────────────────────────────────────────────────────────────
        // NOTE: NotificationService().init() and
        //       PushMessagingService.instance.init() are NO LONGER called
        //       here at startup.
        //
        // - Message listeners + token sync → PushMessagingService.init()
        //   is now called once after user logs in (in auth_bootstrap or
        //   your settings screen).
        //
        // - Notification PERMISSION is only requested when the user
        //   explicitly enables notifications in the settings screen via:
        //     PushMessagingService.instance.requestNotificationPermission()
        //
        // - Camera / Microphone permissions are only requested when the
        //   user actually starts a Live session (already lazy).
        //
        // - Image / Video picker permissions are already lazy (safe_image_picker,
        //   safe_video_picker — no changes needed there).
        // ─────────────────────────────────────────────────────────────────

        // Only start silent background listener (no permission dialog shown).
        try {
          await PushMessagingService.instance.init();
        } catch (e, st) {
          await FirebaseCrashlytics.instance.recordError(e, st, fatal: false);
        }
      }

      final Widget app = kIsWeb
          ? const EleagueHubWebApp()
          : DeepLinkGate(child: const EleagueHubApp());

      runApp(
        ProviderScope(
          overrides: [
            prefsServiceProvider.overrideWithValue(prefs),
          ],
          child: app,
        ),
      );
    } catch (fatalError, stackTrace) {
      if (kIsWeb) {
        runApp(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: const Color(0xFF0F172A),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: SingleChildScrollView(
                    child: Text(
                      'CRITICAL BOOT ERROR:\n\n$fatalError\n\n$stackTrace',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
  }, (error, stack) async {
    if (!kIsWeb) {
      try {
        await FirebaseCrashlytics.instance
            .recordError(error, stack, fatal: true);
      } catch (_) {}
    } else {
      debugPrint('Uncaught zone error: $error');
      debugPrintStack(stackTrace: stack);
    }
  });
}
