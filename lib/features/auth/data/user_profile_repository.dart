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

  // ── Auth helpers ──────────────────────────────────────────────────────────

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
        'Your network appears to be offline. '
        'Please check your connection and try again.',
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
            'Your network appears to be offline. '
            'Please check your connection and try again.',
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

  // ── Badge auto-sync ───────────────────────────────────────────────────────

  /// Inspects [profile]'s active plan and ensures the correct badges
  /// are present in Firestore.
  ///
  /// Called:
  ///   • After every successful [activatePlanSubscription] write.
  ///   • At app start via [syncBadgesForCurrentUser].
  ///
  /// Rules:
  ///   Pro  active  → green badge  (expires with plan)
  ///   Elite active → green + gold organizer badge (expires with plan)
  ///   No / expired plan → subscription badges revoked
  ///                       (manual / admin badges are preserved)
  ///
  /// Errors are caught and logged — they never block the caller.
  Future<void> _syncBadgesForProfile(UserProfile profile) async {
    try {
      final sub = profile.planSubscription;

      if (sub == null || !sub.isActive) {
        // No active plan — revoke any subscription-sourced badges.
        await BadgeService.instance
            .onProSubscriptionExpired(profile.userId);
        await BadgeService.instance
            .onEliteSubscriptionExpired(profile.userId);
        return;
      }

      // Free plans get no verification badge.
      if (sub.plan.isFree) return;

      final expiresAt =
          DateTime.fromMillisecondsSinceEpoch(sub.expiresAtMs);

      if (sub.plan == MasterLeaguePlan.elite) {
        await BadgeService.instance.onEliteSubscriptionPurchased(
          userId: profile.userId,
          expiresAt: expiresAt,
        );
      } else if (sub.plan == MasterLeaguePlan.pro) {
        await BadgeService.instance.onProSubscriptionPurchased(
          userId: profile.userId,
          expiresAt: expiresAt,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[UserProfileRepository] _syncBadgesForProfile error '
          'for ${profile.userId}: $e',
        );
      }
    }
  }

  /// Call once after every sign-in (including resumed sessions on cold
  /// start) to ensure existing users who already have an active plan
  /// receive the correct badge automatically.
  ///
  /// Safe to call on every cold start — all badge writes are idempotent.
  Future<void> syncBadgesForCurrentUser() async {
    try {
      final uid = _auth.currentUser?.uid.trim() ?? '';
      if (uid.isEmpty) return;

      final profile = await fetchByUserIdForBootstrap(uid);
      if (profile == null) return;

      await _syncBadgesForProfile(profile);

      if (kDebugMode) {
        debugPrint(
          '[UserProfileRepository] syncBadgesForCurrentUser '
          'completed for $uid '
          'plan=${profile.activePlanId} '
          'expires=${profile.planExpiresAtMs}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[UserProfileRepository] syncBadgesForCurrentUser '
          'error: $e',
        );
      }
    }
  }

  // ── Display name helpers ──────────────────────────────────────────────────

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

  String displayNameForProfile(
    UserProfile? profile, {
    String fallbackUserId = '',
  }) {
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
    List<String> userIds,
  ) async {
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

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<UserProfile?> fetchByUserId(String userId) async {
    try {
      _requireAuthUid();

      final uid = userId.trim();
      if (uid.isEmpty) return null;

      final snap = await _usersCol
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      if (!snap.exists) return null;
      return UserProfile.fromDoc(snap);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
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
          'UserProfileRepository.fetchByUserIdForBootstrap '
          'server read failed: $e',
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
          'UserProfileRepository.fetchByUserIdForBootstrap '
          'cache read failed: $e',
        );
      }
    }

    return null;
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

  Future<Map<String, UserProfile>> fetchByUserIds(
    List<String> userIds,
  ) async {
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
        final end = (i + chunkSize < ids.length)
            ? i + chunkSize
            : ids.length;
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
            'UserProfileRepository.profileExists fallback=true '
            'for existing auth user: $uid',
          );
        }
        return true;
      }
    }

    return false;
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  Stream<UserProfile?> watchByUserId(String userId) {
    try {
      _requireAuthUid();

      final uid = userId.trim();
      if (uid.isEmpty) return Stream<UserProfile?>.value(null);

      return _usersCol.doc(uid).snapshots().map((snap) {
        if (!snap.exists) return null;
        return UserProfile.fromDoc(snap);
      });
    } catch (_) {
      return const Stream<UserProfile?>.empty();
    }
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

  // ── Writes ────────────────────────────────────────────────────────────────

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

      await _usersCol
          .doc(authUid)
          .set(payload, SetOptions(merge: true))
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Activates the plan subscription in Firestore then auto-grants
  /// the correct verification badge.
  ///
  /// The write is intentionally split into THREE separate atomic
  /// set(merge:true) calls so that each call matches exactly ONE
  /// of the allowed key-sets in the Firestore security rules:
  ///
  ///   Write 1 — plan fields only          → rule branch 1f
  ///   Write 2 — isPremium compat fields   → rule branch 1e  (Pro/Elite)
  ///   Write 3 — verification badge map    → rule branch 1h  (isBadgeSelfWrite)
  ///
  /// Combining writes 1 + 2 into a single call is also permitted by
  /// rule branch 1g, but splitting is safer because it avoids the
  /// Firestore SDK's merge-ordering edge cases when offline cache is
  /// involved.
  Future<void> activatePlanSubscription({
    required MasterLeaguePlan plan,
    required PlanDuration duration,
    required String receiptId,
    required String provider,
  }) async {
    try {
      final authUid = _requireAuthUid();
      final now = DateTime.now().millisecondsSinceEpoch;
      final int expiresAtMs =
          plan.isFree ? 0 : duration.expiryMsFromNow();

      // ── Write 1: Plan fields only (rule branch 1f) ────────────────────
      await _usersCol.doc(authUid).set(
        <String, dynamic>{
          'userId': authUid,
          'activePlanId': plan.id,
          'activePlanDurationId': duration.id,
          'planPurchasedAtMs': now,
          'planExpiresAtMs': expiresAtMs,
          'planReceiptId': receiptId,
          'planProvider': provider,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 20));

      // ── Write 2: isPremium backward-compat (rule branch 1e) ───────────
      // Only written for paid plans (Pro / Elite). Basic / free plans
      // never set isPremium.
      if (plan == MasterLeaguePlan.pro ||
          plan == MasterLeaguePlan.elite) {
        await _usersCol.doc(authUid).set(
          <String, dynamic>{
            'userId': authUid,
            'isPremium': true,
            'premiumExpiresAtMs': expiresAtMs,
            'updatedAt': now,
          },
          SetOptions(merge: true),
        ).timeout(const Duration(seconds: 20));
      }

      // ── Write 3: Verification badge (rule branch 1h) ──────────────────
      // Build a minimal synthetic profile from the data we just wrote so
      // that _syncBadgesForProfile can decide which badge to grant without
      // a second Firestore round-trip. Badge grant errors are caught
      // inside _syncBadgesForProfile and never propagate here.
      final syntheticProfile = UserProfile(
        userId: authUid,
        teamName: '',
        authProvider: provider,
        createdAtMs: now,
        updatedAtMs: now,
        shareId: '',
        quickMessagesCustom: const [],
        photoUrl: '',
        profileImageUrl: '',
        teamImageUrl: '',
        isPremium: plan == MasterLeaguePlan.pro ||
            plan == MasterLeaguePlan.elite,
        premiumExpiresAtMs: expiresAtMs,
        isVerified: false,
        verifiedAtMs: 0,
        verificationExpiresAtMs: 0,
        verificationStatus: '',
        activePlanId: plan.id,
        activePlanDurationId: duration.id,
        planPurchasedAtMs: now,
        planExpiresAtMs: expiresAtMs,
        planReceiptId: receiptId,
        planProvider: provider,
      );

      await _syncBadgesForProfile(syntheticProfile);

      if (kDebugMode) {
        debugPrint(
          '[UserProfileRepository] activatePlanSubscription '
          'completed for $authUid '
          'plan=${plan.id} duration=${duration.id} '
          'provider=$provider expiresAtMs=$expiresAtMs',
        );
      }
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
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

      await _usersCol.doc(targetUid).set(
        <String, dynamic>{
          'userId': targetUid,
          'teamName': value,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 20));
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

      final derived =
          UserProfile.deriveShareIdFromUid(authUid).trim();
      if (derived.isEmpty) return;

      await _usersCol.doc(authUid).set(
        <String, dynamic>{
          'userId': authUid,
          'shareId': derived,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> updateQuickMessages(
    List<String> quickMessages,
  ) async {
    try {
      final authUid = _requireAuthUid();
      final values = quickMessages
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .take(15)
          .toList(growable: false);

      await _usersCol.doc(authUid).set(
        <String, dynamic>{
          'userId': authUid,
          'quickMessagesCustom': values,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 20));
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

      await _usersCol.doc(targetUid).set(
        <String, dynamic>{
          'userId': targetUid,
          'quickMessagesCustom': values,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 20));
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

      if (photoUrl != null) {
        payload['photoUrl'] = photoUrl.trim();
      }
      if (profileImageUrl != null) {
        payload['profileImageUrl'] = profileImageUrl.trim();
      }
      if (teamImageUrl != null) {
        payload['teamImageUrl'] = teamImageUrl.trim();
      }

      await _usersCol
          .doc(authUid)
          .set(payload, SetOptions(merge: true))
          .timeout(const Duration(seconds: 20));
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