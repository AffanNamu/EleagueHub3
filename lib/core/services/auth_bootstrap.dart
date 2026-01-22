import 'package:firebase_auth/firebase_auth.dart';
import '../persistence/prefs_service.dart';

class AuthBootstrap {
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

    // Debug
    // ignore: avoid_print
    print('AuthBootstrap → signed in uid=${user.uid} isAnonymous=${user.isAnonymous}');

    // Persist to your app prefs
    try {
      await prefs.setCurrentUserId(user.uid);
    } catch (_) {
      try {
        await prefs.setString(PreferencesService.kCurrentUserIdKey, user.uid);
      } catch (_) {}
    }

    return user.uid;
  }
}
