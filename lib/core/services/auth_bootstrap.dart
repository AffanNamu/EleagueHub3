import 'package:firebase_auth/firebase_auth.dart';
import '../persistence/prefs_service.dart';

class AuthBootstrap {
  /// Ensures there is a Firebase user (anonymous).
  /// Also persists uid into PreferencesService so the app uses a real user id.
  static Future<String> ensureSignedIn(PreferencesService prefs) async {
    final auth = FirebaseAuth.instance;

    User? user = auth.currentUser;
    if (user == null) {
      final cred = await auth.signInAnonymously();
      user = cred.user;
    }

    if (user == null) {
      throw StateError('FirebaseAuth anonymous sign-in failed (user == null)');
    }

    // Persist to your app prefs (so your code doesn't fall back to "admin_user")
    // We try both common methods/keys to match your PreferencesService.
    try {
      await prefs.setCurrentUserId(user.uid);
    } catch (_) {
      // fallback: write directly to known key if setCurrentUserId doesn't exist
      try {
        await prefs.setString(PreferencesService.kCurrentUserIdKey, user.uid);
      } catch (_) {}
    }

    return user.uid;
  }
}
