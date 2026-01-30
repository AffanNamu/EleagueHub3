import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User identity for leagues.
///
/// Firebase Auth uid is the GLOBAL, IMMUTABLE userId.
class CurrentUser {
  static const _kKey = 'leagues.currentUserId';

  static Future<String> getUserId() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      throw StateError('Not signed in (FirebaseAuth.currentUser == null)');
    }

    // Keep prefs in sync (useful for offline cache layers).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, authUser.uid);

    return authUser.uid;
  }
}
