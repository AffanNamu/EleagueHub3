import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// User identity for leagues.
///
/// Priority:
/// 1) FirebaseAuth uid (required for Firestore rules)
/// 2) Fallback offline UUID (only if auth not available)
class CurrentUser {
  static const _kKey = 'leagues.currentUserId';

  static Future<String> getOrCreateUserId() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser != null) {
      // Keep prefs in sync (nice for offline logic)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, authUser.uid);
      return authUser.uid;
    }

    // Fallback (should not happen if you enabled anonymous auth bootstrap)
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_kKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final id = const Uuid().v4();
    await prefs.setString(_kKey, id);
    return id;
  }
}
