// lib/core/services/app_startup_service.dart
//
// Call AppStartupService.instance.onUserSignedIn(uid) from your
// FirebaseAuth.instance.authStateChanges() listener whenever a
// non-null user is received.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../features/auth/data/user_profile_repository.dart';

class AppStartupService {
  AppStartupService._();
  static final AppStartupService instance = AppStartupService._();
  bool _badgesSyncedThisSession = false;

  /// Call once after every sign-in (including resumed sessions on cold start).
  ///
  /// Safe to call multiple times — runs only once per app session.
  Future<void> onUserSignedIn(String uid) async {
    if (uid.trim().isEmpty) return;
    if (_badgesSyncedThisSession) return;
    
    _badgesSyncedThisSession = true;
    
    try {
      await UserProfileRepository().syncBadgesForCurrentUser();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[AppStartupService] onUserSignedIn badge sync error: $e',
        );
      }
    }
  }

  /// Reset session flag on sign-out so the next sign-in syncs again.
  void onUserSignedOut() {
    _badgesSyncedThisSession = false;
  }
}
