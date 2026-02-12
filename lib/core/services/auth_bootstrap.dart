import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

import '../persistence/prefs_service.dart';

/// ONLINE-ONLY MIGRATION:
/// - Do NOT persist auth identity to local storage for access control.
/// - Always trust `FirebaseAuth.instance.currentUser`.
/// - This helper may optionally ensure an authenticated session (e.g., anonymous),
///   but should never be used as an "offline auth cache".
class AuthBootstrap {
  /// Backward-compatible method signature kept.
  ///
  /// ONLINE-ONLY behavior:
  /// - Optionally signs in anonymously if enabled and no user exists.
  /// - Does NOT store `uid` in SharedPreferences (no local auth assumptions).
  static Future<void> syncCurrentUserToPrefs(
    PreferencesService prefs, {
    bool autoSignInAnonymously = false,
  }) async {
    // prefs is intentionally unused for auth identity in online-only mode.
    // ignore: unused_local_variable
    final PreferencesService _ = prefs;

    final auth = FirebaseAuth.instance;

    if (auth.currentUser != null) return;

    if (!autoSignInAnonymously) return;

    try {
      await auth.signInAnonymously().timeout(const Duration(seconds: 15));
    } on FirebaseAuthException {
      // Silent: app remains signed-out; router/login flow should handle it.
      return;
    } on TimeoutException {
      return;
    } on SocketException {
      return;
    } catch (_) {
      return;
    }
  }
}
