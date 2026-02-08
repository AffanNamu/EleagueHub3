import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User identity for leagues.
///
/// Firebase Auth uid is the GLOBAL, IMMUTABLE userId.
class CurrentUser {
  static const _kKey = 'leagues.currentUserId';

  /// Keep compatibility with PreferencesService.kCurrentUserIdKey as well.
  static const _kPrefsServiceKey = 'current_user_id';

  /// Returns the authenticated Firebase Auth uid.
  ///
  /// Throws if no user is signed in.
  static Future<String> getUserId() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      throw StateError('Not signed in (FirebaseAuth.currentUser == null)');
    }

    // Keep prefs in sync (useful for offline cache layers).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, authUser.uid);

    // Also set the app-wide key used by PreferencesService (sync pull uses this).
    await prefs.setString(_kPrefsServiceKey, authUser.uid);

    return authUser.uid;
  }

  /// Backwards-compatible API used by older call sites.
  ///
  /// IMPORTANT: We do NOT create any local/generated user id. The only userId
  /// allowed is Firebase Auth uid.
  static Future<String> getOrCreateUserId() => getUserId();

  /// Returns the last known uid stored locally (if any).
  ///
  /// This is intended only for cache layers; do NOT treat it as authoritative
  /// identity if the user is signed out.
  static Future<String?> getCachedUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kKey) ?? prefs.getString(_kPrefsServiceKey);
  }
}
