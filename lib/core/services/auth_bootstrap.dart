import 'package:firebase_auth/firebase_auth.dart';

import '../persistence/prefs_service.dart';

class AuthBootstrap {
  /// Syncs SharedPreferences with the currently signed-in Firebase user (if any).
  ///
  /// IMPORTANT (production):
  /// - Firestore rules require `request.auth != null` for leagues/coupons.
  /// - If the app is allowed to work without an explicit login screen, we must
  ///   ensure there is *at least* an anonymous Firebase session.
  ///
  /// If [autoSignInAnonymously] is true and no user is signed in, we will attempt
  /// `FirebaseAuth.signInAnonymously()` to avoid constant permission-denied.
  static Future<void> syncCurrentUserToPrefs(
    PreferencesService prefs, {
    bool autoSignInAnonymously = true,
  }) async {
    final auth = FirebaseAuth.instance;
    var user = auth.currentUser;

    if (user == null && autoSignInAnonymously) {
      try {
        await auth.signInAnonymously();
      } catch (e) {
        // If Anonymous auth is disabled in Firebase Console, this will fail with
        // operation-not-allowed. We keep the app in signed-out mode in that case.
        // ignore: avoid_print
        print('AuthBootstrap → signInAnonymously failed: $e');
      }
      user = auth.currentUser;
    }

    if (user == null) {
      await prefs.clearCurrentUserId();
      // ignore: avoid_print
      print('AuthBootstrap → no Firebase user; prefs cleared');
      return;
    }

    await prefs.setCurrentUserId(user.uid);

    // Debug
    // ignore: avoid_print
    print(
      'AuthBootstrap → current uid=${user.uid} '
      'anon=${user.isAnonymous} '
      'provider=${user.providerData.map((e) => e.providerId).join(",")}',
    );
  }
}
