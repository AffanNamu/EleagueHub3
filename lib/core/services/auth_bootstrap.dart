import 'package:firebase_auth/firebase_auth.dart';
import '../persistence/prefs_service.dart';

class AuthBootstrap {
  /// Syncs SharedPreferences with the currently signed-in Firebase user (if any).
  /// Does NOT sign users in automatically.
  static Future<void> syncCurrentUserToPrefs(PreferencesService prefs) async {
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;

    if (user == null) {
      await prefs.clearCurrentUserId();
      return;
    }

    await prefs.setCurrentUserId(user.uid);

    // Debug
    // ignore: avoid_print
    print(
      'AuthBootstrap → current uid=${user.uid} provider=${user.providerData.map((e) => e.providerId).join(",")}',
    );
  }
}
