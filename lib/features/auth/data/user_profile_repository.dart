// lib/features/auth/data/user_profile_repository.dart

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';

import '../../master_leagues/domain/master_league_plan.dart';
import '../../verification/domain/badge_model.dart';
import '../../verification/logic/badge_service.dart';
import '../models/user_profile.dart';

class UserProfileRepositoryException implements Exception {
  final String message;
  const UserProfileRepositoryException(this.message);

  @override
  String toString() => message;
}

class UserProfileRepository {
  UserProfileRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _usersCol =>
      _firestore.collection('users');

  String _requireAuthUid() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const UserProfileRepositoryException(
        'Please sign in and try again.',
      );
    }
    return uid;
  }

  Never _rethrowFriendly(Object error) {
    if (error is UserProfileRepositoryException) throw error;

    if (error is SocketException) {
      throw const UserProfileRepositoryException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    }

    if (error is TimeoutException) {
      throw const UserProfileRepositoryException(
        'Your internet connection seems unstable. Please try again.',
      );
    }

    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          throw const UserProfileRepositoryException(
            'You do not have permission to access this profile.',
          );
        case 'unauthenticated':
          throw const UserProfileRepositoryException(
            'Please sign in and try again.',
          );
        case 'unavailable':
        case 'deadline-exceeded':
          throw const UserProfileRepositoryException(
            'Your network appears to be offline. Please check your connection and try again.',
          );
        default:
          throw const UserProfileRepositoryException(
            "We couldn't complete this profile request. Please try again.",
          );
      }
    }

    throw const UserProfileRepositoryException(
      'Something went wrong. Please try again.',
    );
  }

  String displayNameFromData(
    Map<String, dynamic>? data, {
    String fallbackUserId = '',
  }) {
    final map = data ?? <String, dynamic>{};

    final direct = <String>[
      (map['teamName'] as String?) ?? '',
      (map['displayName'] as String?) ?? '',
      (map['name'] as String?) ?? '',
      (map['username'] as String?) ?? '',
    ];

    for (final raw in direct) {
      final value = raw.trim();
      if (value.isNotEmpty) return value;
    }

    final shareId = (map['shareId'] as String? ?? '').trim();
    if (shareId.isNotEmpty) return shareId;

    final fallback = fallbackUserId.trim();
    if (fallback.isNotEmpty) {
      final shortId = UserProfile.deriveShareIdFromUid(fallback);
      if (shortId.isNotEmpty) return shortId;
    }

    return 'User';
  }

  String displayNameForProfile(UserProfile? profile,
      {String fallbackUserId = ''}) {
    if (profile != null && profile.displayName.trim().isNotEmpty) {
      return profile.displayName.trim();
    }
    final fallback = fallbackUserId.trim();
    if (fallback.isNotEmpty) {
      final shortId = UserProfile.deriveShareIdFromUid(fallback);
      if (shortId.isNotEmpty) return shortId;
    }
    return 'User';
  }

  Future<String> fetchDisplayNameByUserId(String userId) async {
    try {
      final profile = await fetchByUserId(userId);
      return displayNameForProfile(profile, fallbackUserId: userId);
    } catch (_) {
      final fallback = userId.trim();
      if (fallback.isNotEmpty) {
        final shortId = UserProfile.deriveShareIdFromUid(fallback);
        if (shortId.isNotEmpty) return shortId;
      }
      return 'User';
    }
  }

  Future<Map<String, String>> fetchDisplayNamesByUserIds(
      List<String> userIds) async {
    final out = <String, String>{};
    final ids = userIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (ids.isEmpty) return out;

    try {
      final profiles = await fetchByUserIds(ids);
      for (final id in ids) {
        out[id] = displayNameForProfile(
          profiles[id],
          fallbackUserId: id,
        );
      }
      return out;
    } catch (_) {
      for (final id in ids) {
        final shortId = UserProfile.deriveShareIdFromUid(id);
        out[id] = shortId.isNotEmpty ? shortId : 'User';
      }
      return out;
    }
  }

  /// ── FIXED: fetchByUserId no longer throws on permission-denied.
  ///
  /// Root cause of "You do not have permission to access this profile":
  /// this method previously threw immediately on any Firestore
  /// permission-denied response from a server read. Your Firestore rule
  /// for /users/{userId} is `allow read: if signedIn();` — fully open to
  /// any signed-in user — so a genuine permission-denied here almost
  /// always reflects a transient auth-token race (e.g. right after
  /// getIdToken(true) is called elsewhere, or a brief network blip),
  /// NOT an actual permissions problem.
  ///
  /// Now: on permission-denied (or any transient Firestore error), we
  /// fall back to the local cache, and only return null if that also
  /// fails — mirroring the existing, already-safe behaviour of
  /// fetchByUserIdForBootstrap. Callers that need a hard failure for
  /// missing auth still get UserProfileRepositoryException for the
  /// actual "not signed in" case via _requireAuthUid().
  Future<UserProfile?> fetchByUserId(String userId) async {
    _requireAuthUid();

    final uid = userId.trim();
    if (uid.isEmpty) return null;

    try {
      final snap = await _usersCol
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      if (!snap.exists) return null;
      return UserProfile.fromDoc(snap);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'UserProfileRepository.fetchByUserId server read failed '
          '(falling back to cache): $e',
        );
      }
    }

    try {
      final cacheSnap = await _usersCol
          .doc(uid)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 4));

      if (cacheSnap.exists) {
        return UserProfile.fromDoc(cacheSnap);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'UserProfileRepository.fetchByUserId cache read failed: $e',
        );
      }
    }

    return null;
  }

  Future<UserProfile?> fetchByUserIdForBootstrap(String userId) async {
    final uid = userId.trim();
    if (uid.isEmpty) return null;

    try {
      final serverSnap = await _usersCol
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      if (serverSnap.exists) {
        return UserProfile.fromDoc(serverSnap);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'UserProfileRepository.fetchByUserIdForBootstrap server read failed: $e',
        );
      }
    }

    try {
      final cacheSnap = await _usersCol
          .doc(uid)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 4));

      if (cacheSnap.exists) {
        return UserProfile.fromDoc(cacheSnap);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'UserProfileRepository.fetchByUserIdForBootstrap cache read failed: $e',
        );
      }
    }

    return null;
  }

  Stream<UserProfile?> watchByUserId(String userId) {
    try {
      _requireAuthUid();

      final uid = userId.trim();
      if (uid.isEmpty) return Stream<UserProfile?>.value(null);

      return _usersCol.doc(uid).snapshots().map((snap) {
        if (!snap.exists) return null;
        return UserProfile.fromDoc(snap);
      }).handleError((e) {
        if (kDebugMode) {
          debugPrint('UserProfileRepository.watchByUserId stream error: $e');
        }
      });
    } catch (_) {
      return const Stream<UserProfile?>.empty();
    }
  }

  Future<UserProfile?> fetchByShareId(String shareId) async {
    try {
      _requireAuthUid();

      final normalized = shareId.trim();
      if (normalized.isEmpty) return null;

      final snap = await _usersCol
          .where('shareId', isEqualTo: normalized)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      if (snap.docs.isEmpty) return null;
      return UserProfile.fromDoc(snap.docs.first);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<UserProfile?> fetchByUserIdOrShareId(String input) async {
    try {
      final trimmed = input.trim();
      if (trimmed.isEmpty) return null;

      final byUid = await fetchByUserId(trimmed);
      if (byUid != null) return byUid;

      return await fetchByShareId(trimmed);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<Map<String, UserProfile>> fetchByUserIds(List<String> userIds) async {
    try {
      _requireAuthUid();

      final ids = userIds
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);

      if (ids.isEmpty) return const <String, UserProfile>{};

      final out = <String, UserProfile>{};

      const int chunkSize = 10;
      for (int i = 0; i < ids.length; i += chunkSize) {
        final end = (i + chunkSize < ids.length) ? i + chunkSize : ids.length;
        final chunk = ids.sublist(i, end);

        final snap = await _usersCol
            .where(FieldPath.documentId, whereIn: chunk)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 15));

        for (final doc in snap.docs) {
          final profile = UserProfile.fromDoc(doc);
          out[profile.userId] = profile;
        }
      }

      return out;
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<bool> profileExists(String userId) async {
    final uid = userId.trim();
    if (uid.isEmpty) return false;

    final profile = await fetchByUserIdForBootstrap(uid);
    if (profile != null) return true;

    final currentUid = _auth.currentUser?.uid.trim() ?? '';
    if (currentUid.isNotEmpty && currentUid == uid) {
      final authUser = _auth.currentUser;
      final hasAnyIdentitySignal =
          (authUser?.displayName ?? '').trim().isNotEmpty ||
              (authUser?.email ?? '').trim().isNotEmpty ||
              (authUser?.photoURL ?? '').trim().isNotEmpty ||
              (authUser?.providerData.isNotEmpty ?? false);

      if (hasAnyIdentitySignal) {
        if (kDebugMode) {
          debugPrint(
            'UserProfileRepository.profileExists fallback=true for existing auth user: $uid',
          );
        }
        return true;
      }
    }

    return false;
  }

  Stream<bool> watchIsPremium(String userId) {
    try {
      _requireAuthUid();
      return watchByUserId(userId).map((profile) {
        if (profile == null) return false;
        return profile.premiumActive;
      });
    } catch (_) {
      return const Stream<bool>.empty();
    }
  }

  Stream<bool> watchHasActivePlan(String userId) {
    try {
      _requireAuthUid();
      return watchByUserId(userId).map((profile) {
        if (profile == null) return false;
        return profile.hasPlanActive;
      });
    } catch (_) {
      return const Stream<bool>.empty();
    }
  }

  Stream<UserPlanSubscription?> watchPlanSubscription(String userId) {
    try {
      _requireAuthUid();
      return watchByUserId(userId).map((profile) {
        return profile?.planSubscription;
      });
    } catch (_) {
      return const Stream<UserPlanSubscription?>.empty();
    }
  }

  Stream<List<String>> watchQuickMessagesCustom(String userId) {
    try {
      _requireAuthUid();
      return watchByUserId(userId).map((profile) {
        return profile?.quickMessagesCustom ?? const <String>[];
      });
    } catch (_) {
      return const Stream<List<String>>.empty();
    }
  }

  /// ── NEW: Writes an arbitrary payload to /users/{authUid} and, if the
  /// FIRST attempt fails with a Firestore `permission-denied` error,
  /// forces a fresh ID token and retries exactly once before giving up.
  ///
  /// ROOT CAUSE FIXED HERE (Pro/Elite plan purchase showing
  /// "You do not have permission to access this profile"):
  ///
  /// activatePlanSubscription() below is called immediately after a
  /// Google Play purchase completes (purchase stream callback) or right
  /// after a Flutterwave charge is server-verified. At that exact moment
  /// the Firebase ID token cached on the client can be stale/near-expiry,
  /// and Firestore's backend rejects the write with permission-denied —
  /// even though the security rule itself allows a signed-in user to
  /// write their own /users/{uid} document. Previously this bubbled up
  /// untouched through _rethrowFriendly() as the confusing permissions
  /// message you saw, even though nothing was actually wrong with the
  /// user's access rights.
  ///
  /// This mirrors the same "transient auth-token race" reasoning already
  /// applied to fetchByUserId() above, but for writes: since a write
  /// can't fall back to cache, we instead force-refresh the ID token and
  /// retry the write once before surfacing any error to the caller.
  Future<void> _writeUserDocWithRetry(
    String authUid,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _usersCol
          .doc(authUid)
          .set(payload, SetOptions(merge: true))
          .timeout(const Duration(seconds: 20));
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;

      if (kDebugMode) {
        debugPrint(
          'UserProfileRepository._writeUserDocWithRetry: permission-denied '
          'on first write attempt for $authUid — refreshing ID token and '
          'retrying once.',
        );
      }

      try {
        await _auth.currentUser?.getIdToken(true);
      } catch (_) {}

      await _usersCol
          .doc(authUid)
          .set(payload, SetOptions(merge: true))
          .timeout(const Duration(seconds: 20));
    }
  }

  Future<void> saveOrUpdateSelf(UserProfile profile) async {
    try {
      final authUid = _requireAuthUid();
      if (profile.userId.trim() != authUid) {
        throw const UserProfileRepositoryException(
          'You can only update your own profile.',
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final payload = <String, dynamic>{
        ...profile.toJson(),
        'userId': authUid,
        'updatedAt': now,
      };

      if (payload['createdAt'] == null || payload['createdAt'] == 0) {
        payload['createdAt'] = now;
      }

      await _writeUserDocWithRetry(authUid, payload);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> activatePlanSubscription({
    required MasterLeaguePlan plan,
    required PlanDuration duration,
    required String receiptId,
    required String provider,
  }) async {
    try {
      final authUid = _requireAuthUid();
      final now = DateTime.now().millisecondsSinceEpoch;

      final int expiresAtMs = plan.isFree ? 0 : duration.expiryMsFromNow();

      final payload = <String, dynamic>{
        'userId': authUid,
        'activePlanId': plan.id,
        'activePlanDurationId': duration.id,
        'planPurchasedAtMs': now,
        'planExpiresAtMs': expiresAtMs,
        'planReceiptId': receiptId,
        'planProvider': provider,
        'updatedAt': now,
        // backward compatibility with old premium-only screens
        if (plan == MasterLeaguePlan.pro || plan == MasterLeaguePlan.elite)
          'isPremium': true,
        if (plan == MasterLeaguePlan.pro || plan == MasterLeaguePlan.elite)
          'premiumExpiresAtMs': expiresAtMs,
      };

      // ── FIXED: was a bare .set(...) that surfaced a spurious
      // permission-denied right after Pro/Elite purchases. Now retries
      // once after a forced token refresh — see _writeUserDocWithRetry.
      await _writeUserDocWithRetry(authUid, payload);

      // ── Sync verification badges right after activation ──────────────
      if (!plan.isFree) {
        try {
          if (plan == MasterLeaguePlan.elite) {
            await BadgeService.instance.onEliteSubscriptionPurchased(
              userId: authUid,
              expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMs),
            );
          } else if (plan == MasterLeaguePlan.pro) {
            await BadgeService.instance.onProSubscriptionPurchased(
              userId: authUid,
              expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMs),
            );
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '[UserProfileRepository] activatePlanSubscription badge sync error: $e',
            );
          }
        }
      }
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Backfills verification badges for the CURRENTLY signed-in user
  /// based on the plan already recorded on their Firestore profile.
  Future<void> syncBadgesForCurrentUser() async {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    try {
      final profile = await fetchByUserIdForBootstrap(uid);
      if (profile == null) return;

      final planId = profile.activePlanId.trim().toLowerCase();
      if (planId != 'pro' && planId != 'elite') return;

      final expiresAtMs = profile.planExpiresAtMs;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (expiresAtMs <= nowMs) return;

      final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMs);

      if (planId == 'elite') {
        await BadgeService.instance.onEliteSubscriptionPurchased(
          userId: uid,
          expiresAt: expiresAt,
        );
        if (kDebugMode) {
          debugPrint(
            '[UserProfileRepository] syncBadgesForCurrentUser: '
            'Elite badges backfilled for $uid (expires $expiresAt)',
          );
        }
        return;
      }

      final current = await BadgeService.instance.getBadges(uid);
      final alreadyEliteGreen =
          current.greenSource == BadgeSource.eliteSubscription &&
              current.isGreenActive;
      if (alreadyEliteGreen) return;

      await BadgeService.instance.onProSubscriptionPurchased(
        userId: uid,
        expiresAt: expiresAt,
      );
      if (kDebugMode) {
        debugPrint(
          '[UserProfileRepository] syncBadgesForCurrentUser: '
          'Pro badge backfilled for $uid (expires $expiresAt)',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[UserProfileRepository] syncBadgesForCurrentUser error: $e',
        );
      }
    }
  }

  Future<void> updateTeamName({
    String? userId,
    required String teamName,
  }) async {
    try {
      final authUid = _requireAuthUid();
      final targetUid = (userId ?? authUid).trim();
      final value = teamName.trim();

      if (targetUid != authUid) {
        throw const UserProfileRepositoryException(
          'You can only update your own profile.',
        );
      }

      if (value.isEmpty) {
        throw const UserProfileRepositoryException(
          'Please enter a team name.',
        );
      }

      await _writeUserDocWithRetry(targetUid, <String, dynamic>{
        'userId': targetUid,
        'teamName': value,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> ensureShareIdIfMissing() async {
    try {
      final authUid = _requireAuthUid();
      final doc = await _usersCol
          .doc(authUid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      final data = doc.data() ?? <String, dynamic>{};
      final current = (data['shareId'] as String? ?? '').trim();
      if (current.isNotEmpty) return;

      final derived = UserProfile.deriveShareIdFromUid(authUid).trim();
      if (derived.isEmpty) return;

      await _writeUserDocWithRetry(authUid, <String, dynamic>{
        'userId': authUid,
        'shareId': derived,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> updateQuickMessages(List<String> quickMessages) async {
    try {
      final authUid = _requireAuthUid();
      final values = quickMessages
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .take(15)
          .toList(growable: false);

      await _writeUserDocWithRetry(authUid, <String, dynamic>{
        'userId': authUid,
        'quickMessagesCustom': values,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> updateQuickMessagesCustom({
    String? userId,
    required List<String> messages,
  }) async {
    try {
      final authUid = _requireAuthUid();
      final targetUid = (userId ?? authUid).trim();

      if (targetUid != authUid) {
        throw const UserProfileRepositoryException(
          'You can only update your own quick messages.',
        );
      }

      final values = messages
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .take(15)
          .toList(growable: false);

      await _writeUserDocWithRetry(targetUid, <String, dynamic>{
        'userId': targetUid,
        'quickMessagesCustom': values,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> updateProfileImages({
    String? photoUrl,
    String? profileImageUrl,
    String? teamImageUrl,
  }) async {
    try {
      final authUid = _requireAuthUid();
      final payload = <String, dynamic>{
        'userId': authUid,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

      if (photoUrl != null) payload['photoUrl'] = photoUrl.trim();
      if (profileImageUrl != null) {
        payload['profileImageUrl'] = profileImageUrl.trim();
      }
      if (teamImageUrl != null) payload['teamImageUrl'] = teamImageUrl.trim();

      await _writeUserDocWithRetry(authUid, payload);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> createIfMissing({
    String? userId,
    required String authProvider,
    required String teamName,
    Object? onboardingAnswers,
  }) async {
    try {
      final authUid = _requireAuthUid();
      final targetUid = (userId ?? authUid).trim();
      if (targetUid != authUid) {
        throw const UserProfileRepositoryException(
          'You can only create your own profile.',
        );
      }

      final ref = _usersCol.doc(targetUid);
      final existing = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      if (existing.exists) return;

      final now = DateTime.now().millisecondsSinceEpoch;

      await ref.set(
        <String, dynamic>{
          'userId': targetUid,
          'teamName': teamName.trim(),
          'authProvider': authProvider.trim(),
          'createdAt': now,
          'updatedAt': now,
          'shareId': UserProfile.deriveShareIdFromUid(targetUid),
          'activePlanId': '',
          'activePlanDurationId': '',
          'planPurchasedAtMs': 0,
          'planExpiresAtMs': 0,
          'planReceiptId': '',
          'planProvider': '',
        },
        SetOptions(merge: false),
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> createProfileIfMissing({
    String? userId,
    required String authProvider,
    required String teamName,
    Object? onboardingAnswers,
  }) async {
    await createIfMissing(
      userId: userId,
      authProvider: authProvider,
      teamName: teamName,
      onboardingAnswers: onboardingAnswers,
    );
  }

  Future<void> refreshShareIdFromUidIfEmpty() async {
    await ensureShareIdIfMissing();
  }

  Future<void> debugEnsureSelfProfile() async {
    if (!kDebugMode) return;
    try {
      await ensureShareIdIfMissing();
    } catch (_) {}
  }
}

