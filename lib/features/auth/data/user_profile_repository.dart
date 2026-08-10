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
import '../domain/username_utils.dart';
import '../models/user_profile.dart';

class UserProfileRepositoryException implements Exception {
  final String message;
  const UserProfileRepositoryException(this.message);

  @override
  String toString() => message;
}

/// Thrown specifically when a username is unavailable (already taken
/// by a different user, or reserved). Callers that want a distinct
/// "taken" UI state (as opposed to a generic error) can catch this.
class UsernameUnavailableException extends UserProfileRepositoryException {
  const UsernameUnavailableException(super.message);
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

  /// Top-level collection used purely as an atomic uniqueness
  /// reservation for usernames. Doc ID == canonical lowercase
  /// username. Doc body: {userId, createdAtMs}. This collection is
  /// intentionally separate from `/users/{uid}` so that "is this
  /// username taken" can be answered with a single, cheap, indexed
  /// document read/write instead of a query, and so uniqueness can be
  /// enforced transactionally without contending on the user's own
  /// document for unrelated concurrent writes.
  CollectionReference<Map<String, dynamic>> get _usernamesCol =>
      _firestore.collection('usernames');

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

  // ── FIXED: reverted to a plain server-then-cache read.
  //
  // A previous edit (not from this thread's fixes) added a
  // "SYNCHRONOUS AUTO-HEAL" block here that, whenever the local device
  // cache showed an active paid plan but the SERVER document did not,
  // would automatically WRITE the cached plan data back to the server
  // -- using `receiptId: 'auto_healed_receipt'` when the cached
  // receipt was empty. That is a fabricated, unverifiable receipt ID
  // written directly to Firestore from the client, with no purchase
  // verification of any kind. Any device whose local cache ever
  // contained a "Pro"/"Elite" record (including a genuinely expired
  // one that was merely still numerically in the future relative to
  // some earlier moment, or a corrupted/tampered local database) could
  // silently re-grant itself a paid plan on the next app launch. This
  // is a real security hole and has been removed. Entitlement writes
  // now only ever happen through activatePlanSubscription(), called
  // either directly with a real, provider-verified receipt, or via
  // MasterLeagueEntitlementService.activateAfterPayment(), which for
  // Google Play now routes through the Cloudflare Worker for genuine
  // server-side verification against the Play Developer API before
  // anything is written.
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

  /// Looks up a user by their username (with or without a leading
  /// '@'). Reserved for future use (mentions, "open profile by
  /// username", share links) — not wired into any UI yet, but kept
  /// here alongside the other lookup helpers so this repository stays
  /// the single source of truth for username reads.
  Future<UserProfile?> fetchByUsername(String username) async {
    try {
      _requireAuthUid();

      var normalized = username.trim().toLowerCase();
      if (normalized.startsWith('@')) {
        normalized = normalized.substring(1);
      }
      if (normalized.isEmpty) return null;

      final reservation = await _usernamesCol
          .doc(normalized)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));

      if (!reservation.exists) return null;

      final targetUid =
          (reservation.data()?['userId'] as String? ?? '').trim();
      if (targetUid.isEmpty) return null;

      return await fetchByUserId(targetUid);
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

  /// Ensures a payload will satisfy Firestore's `create` rule for
  /// `/users/{userId}` when the document does not already exist.
  ///
  /// A `.set(data, SetOptions(merge: true))` call is evaluated by
  /// Firestore's `create` rule when the target document does not yet
  /// exist, and by the `update` rule when it does. The `create` rule
  /// requires `keys().hasAll(['userId','teamName','authProvider',
  /// 'createdAt','updatedAt'])`, but activatePlanSubscription() below
  /// only ever sends plan-related fields plus userId/updatedAt. So if
  /// a user's `/users/{uid}` document does not already exist at the
  /// moment they buy Pro/Elite (fresh install, a profile-creation
  /// race, or an account that never went through createIfMissing),
  /// that write would fail `hasAll(...)` and get rejected with
  /// permission-denied. This fills in sane baseline defaults first so
  /// the write is accepted as a valid `create` instead of silently
  /// failing.
  Future<Map<String, dynamic>> _ensureCreateCompliantPayload(
    String authUid,
    Map<String, dynamic> payload,
  ) async {
    final alreadyHasBaseline = payload.containsKey('teamName') &&
        payload.containsKey('authProvider') &&
        payload.containsKey('createdAt');
    if (alreadyHasBaseline) return payload;

    bool docExists = true;
    try {
      final snap = await _usersCol
          .doc(authUid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      docExists = snap.exists;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'UserProfileRepository._ensureCreateCompliantPayload: '
          'server existence check failed, trying cache: $e',
        );
      }
      try {
        final cacheSnap = await _usersCol
            .doc(authUid)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 4));
        docExists = cacheSnap.exists;
      } catch (_) {
        // Unknown — default to "exists" so we don't unnecessarily
        // overwrite a real profile's teamName/authProvider with
        // fallback values. If it genuinely doesn't exist, the write
        // will fail below and be retried/reported normally.
        docExists = true;
      }
    }

    if (docExists) return payload;

    if (kDebugMode) {
      debugPrint(
        'UserProfileRepository._ensureCreateCompliantPayload: '
        '/users/$authUid does not exist yet — injecting baseline '
        'fields (teamName, authProvider, createdAt) so this write '
        'is accepted under the create rule.',
      );
    }

    final authUser = _auth.currentUser;
    final fallbackTeamName = (authUser?.displayName ?? '').trim().isNotEmpty
        ? authUser!.displayName!.trim()
        : 'User';
    final fallbackAuthProvider =
        (authUser?.providerData.isNotEmpty ?? false)
            ? authUser!.providerData.first.providerId.trim()
            : 'unknown';

    return <String, dynamic>{
      'teamName': fallbackTeamName,
      'authProvider':
          fallbackAuthProvider.isNotEmpty ? fallbackAuthProvider : 'unknown',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      ...payload,
    };
  }

  /// Writes an arbitrary payload to /users/{authUid}. If the target
  /// document doesn't exist yet, baseline fields required by the
  /// Firestore `create` rule are injected automatically (see
  /// [_ensureCreateCompliantPayload]). If the FIRST write attempt still
  /// fails with `permission-denied` (e.g. a stale ID token right after
  /// a purchase), forces a fresh ID token and retries exactly once
  /// before giving up.
  Future<void> _writeUserDocWithRetry(
    String authUid,
    Map<String, dynamic> payload,
  ) async {
    final compliantPayload =
        await _ensureCreateCompliantPayload(authUid, payload);

    try {
      await _usersCol
          .doc(authUid)
          .set(compliantPayload, SetOptions(merge: true))
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
          .set(compliantPayload, SetOptions(merge: true))
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

  // ─────────────────────────────────────────────────────────────────────
  // USERNAME SYSTEM
  //
  // Single source of truth for username uniqueness, generation, and
  // editing. All username reads/writes in the app MUST go through
  // this section — never write `username`/`usernameLower` via
  // saveOrUpdateSelf()/toJson() or any other path, or the
  // `usernames/{usernameLower}` reservation collection will desync
  // from `users/{uid}`.
  //
  // Uniqueness is enforced with two SEQUENTIAL writes per attempt
  // (see [_reserveAndWriteUsername] for exactly why this can't be a
  // single runTransaction() the way it originally was):
  //   1. Reserve `usernames/{candidateLower}` (its own small
  //      transaction, so two concurrent attempts at the same
  //      candidate can never both succeed).
  //   2. Once that reservation has actually committed, update
  //      `users/{uid}` with the new username/usernameLower. The
  //      Firestore rule for that update requires the reservation to
  //      already exist, which is now guaranteed since step 1 already
  //      committed before step 2 begins.
  //   3. Best-effort: delete the OLD reservation doc (if any, and if
  //      different).
  // If step 2 fails after step 1 succeeded, the just-created
  // reservation is rolled back (deleted) so a failed save can't
  // permanently squat on a username.
  // ─────────────────────────────────────────────────────────────────────

  /// Best-effort, NON-transactional availability check — safe to call
  /// on every keystroke (debounced) for live UI feedback ("Available"
  /// / "Taken"). This does NOT reserve the name; a final authoritative
  /// check happens again as part of [updateUsername]'s reservation step.
  Future<bool> isUsernameAvailable(String candidate, {String? forUserId}) async {
    try {
      final authUid = _requireAuthUid();
      final selfUid = (forUserId ?? authUid).trim();

      final lower = candidate.trim().toLowerCase();
      if (!UsernameUtils.isValidUsername(lower)) return false;

      final doc = await _usernamesCol
          .doc(lower)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      if (!doc.exists) return true;

      final owner = (doc.data()?['userId'] as String? ?? '').trim();
      return owner.isEmpty || owner == selfUid;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('UserProfileRepository.isUsernameAvailable failed: $e');
      }
      // Fail closed for UI purposes (treat as "can't tell yet") by
      // rethrowing a friendly error the caller can display distinctly
      // from a hard "taken" state.
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Reserves [candidateLower] for [authUid] and points their profile
  /// at it, releasing [previousLower] (if any). Throws
  /// [UsernameUnavailableException] if the candidate is taken by
  /// someone else or fails validation. Returns normally on success.
  ///
  /// FIXED (username save bug): this used to be a single
  /// `runTransaction()` that both created `usernames/{candidateLower}`
  /// AND updated `users/{uid}` in the same transaction. That looked
  /// correct but doesn't work with the security rules as written: the
  /// `users/{uid}` update rule requires
  /// `exists(usernames/{candidateLower})`, and Firestore Security
  /// Rules evaluate every write in a transaction against the database
  /// state as it existed BEFORE that transaction's own writes are
  /// applied — a write earlier in the same transaction is not visible
  /// to a rule check on a later write in that same transaction. So
  /// `exists(...)` was always evaluating to `false` for the brand-new
  /// reservation, and the `users/{uid}` write was silently rejected
  /// with `permission-denied` even for a genuinely available username
  /// (hence: availability check says free, Save says "Something went
  /// wrong"). The fix is to commit the reservation first, THEN update
  /// the profile as a separate write, with rollback if step 2 fails.
  Future<void> _reserveAndWriteUsername({
    required String authUid,
    required String candidateLower,
    required String candidateDisplay,
    required String previousLower,
  }) async {
    if (!UsernameUtils.isValidUsername(candidateLower)) {
      throw const UsernameUnavailableException(
        'That username is not allowed.',
      );
    }

    final newRef = _usernamesCol.doc(candidateLower);
    final userRef = _usersCol.doc(authUid);
    final now = DateTime.now().millisecondsSinceEpoch;

    // ── STEP 1: reserve the new username as its own committed write ──────
    // Kept as a small transaction purely to race-proof it against two
    // people claiming the same candidate at the same instant — NOT
    // combined with step 2 (see doc comment above for why).
    await _firestore.runTransaction((txn) async {
      final newSnap = await txn.get(newRef);
      if (newSnap.exists) {
        final owner = (newSnap.data()?['userId'] as String? ?? '').trim();
        if (owner.isNotEmpty && owner != authUid) {
          throw const UsernameUnavailableException(
            'That username is already taken.',
          );
        }
        // Already reserved by this same user (e.g. a retried call
        // after a prior partial failure) — nothing further to do here.
        return;
      }

      txn.set(newRef, <String, dynamic>{
        'userId': authUid,
        'createdAtMs': now,
      });
    }).timeout(const Duration(seconds: 20));

    // ── STEP 2: point the profile at the now-committed reservation ───────
    try {
      await userRef.set(
        <String, dynamic>{
          'userId': authUid,
          'username': candidateDisplay,
          'usernameLower': candidateLower,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      // Roll back the reservation so a failed save doesn't permanently
      // lock this username away from everyone (including this same
      // user retrying immediately after).
      try {
        final snap = await newRef.get();
        final owner = (snap.data()?['userId'] as String? ?? '').trim();
        if (snap.exists && owner == authUid) {
          await newRef.delete();
        }
      } catch (_) {
        // Best-effort rollback only — surfacing the original error
        // below matters more than this cleanup succeeding.
      }
      rethrow;
    }

    // ── STEP 3: release the OLD reservation, best-effort ──────────────────
    // The profile already points at the new username at this point
    // regardless of whether this cleanup succeeds, so failures here are
    // non-fatal.
    if (previousLower.isNotEmpty && previousLower != candidateLower) {
      try {
        final oldRef = _usernamesCol.doc(previousLower);
        final oldSnap = await oldRef.get();
        final oldOwner = (oldSnap.data()?['userId'] as String? ?? '').trim();
        if (oldSnap.exists && oldOwner == authUid) {
          await oldRef.delete();
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[UserProfileRepository] _reserveAndWriteUsername: failed to '
            'release old reservation "$previousLower" for $authUid '
            '(non-fatal): $e',
          );
        }
      }
    }
  }

  /// Explicit, user-initiated username change. Validates format,
  /// rejects reserved words, and atomically enforces uniqueness. On
  /// success the new username is immediately reflected in
  /// `watchByUserId` (the transaction updates `users/{uid}` too).
  ///
  /// Throws [UsernameUnavailableException] if the name is taken,
  /// reserved, or invalid; a generic [UserProfileRepositoryException]
  /// for network/permission issues.
  Future<void> updateUsername(String newUsername) async {
    try {
      final authUid = _requireAuthUid();
      final candidateLower = newUsername.trim().toLowerCase();

      if (!UsernameUtils.isValidFormat(candidateLower)) {
        throw UsernameUnavailableException(
          'Usernames must be ${UsernameUtils.minLength}-'
          '${UsernameUtils.maxLength} characters: letters, numbers, '
          'and underscore only.',
        );
      }
      if (UsernameUtils.isReserved(candidateLower)) {
        throw const UsernameUnavailableException(
          'That username is reserved. Please choose another.',
        );
      }

      final current = await fetchByUserId(authUid);
      final previousLower = current?.usernameLower.trim() ?? '';

      if (previousLower == candidateLower) {
        // No-op: saving the same username the user already has.
        return;
      }

      await _reserveAndWriteUsername(
        authUid: authUid,
        candidateLower: candidateLower,
        candidateDisplay: candidateLower,
        previousLower: previousLower,
      );
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Lazily assigns a username to the currently signed-in user IF
  /// they don't already have one — for both brand-new accounts and
  /// pre-existing accounts created before the username system
  /// existed. Safe to call repeatedly (no-ops once a username is
  /// set). Does not touch shareId or any unrelated profile field.
  ///
  /// Generation strategy: normalize the display name into a base
  /// candidate, then try `base`, `base1`, `base2`, ... each as a full
  /// atomic reserve-and-write attempt, so there is never a "checked
  /// then someone else took it" gap between generation and
  /// reservation. Silently gives up after a reasonable number of
  /// attempts rather than looping forever or throwing — this runs in
  /// the background from the Profile screen and must never crash it.
  Future<void> ensureUsernameIfMissing() async {
    final authUid = _auth.currentUser?.uid.trim() ?? '';
    if (authUid.isEmpty) return;

    try {
      final profile = await fetchByUserIdForBootstrap(authUid);
      if (profile == null) return;
      if (profile.usernameLower.trim().isNotEmpty) return;

      var base = UsernameUtils.normalizeToBaseUsername(profile.displayName);
      if (base.isEmpty) base = 'user';
      base = UsernameUtils.padToMinLength(base);
      if (base.length > UsernameUtils.maxLength) {
        base = base.substring(0, UsernameUtils.maxLength);
      }

      const maxAttempts = 20;
      for (var i = 0; i <= maxAttempts; i++) {
        final suffix = i == 0 ? '' : '$i';
        var candidate = suffix.isEmpty ? base : base;
        if (suffix.isNotEmpty) {
          final maxBaseLen = UsernameUtils.maxLength - suffix.length;
          final trimmedBase = base.length > maxBaseLen
              ? base.substring(0, maxBaseLen.clamp(1, base.length))
              : base;
          candidate = '$trimmedBase$suffix';
        }

        if (!UsernameUtils.isValidUsername(candidate)) continue;

        try {
          await _reserveAndWriteUsername(
            authUid: authUid,
            candidateLower: candidate,
            candidateDisplay: candidate,
            previousLower: '',
          );
          if (kDebugMode) {
            debugPrint(
              '[UserProfileRepository] ensureUsernameIfMissing: assigned '
              '"$candidate" to $authUid on attempt ${i + 1}.',
            );
          }
          return;
        } on UsernameUnavailableException {
          // Taken — try the next suffix.
          continue;
        }
      }

      // Last-resort: guaranteed-unique suffix derived from the uid
      // itself, so this always terminates successfully.
      final uidTail =
          authUid.replaceAll(RegExp(r'[^a-z0-9]', caseSensitive: false), '')
              .toLowerCase();
      final tail = uidTail.length >= 4
          ? uidTail.substring(uidTail.length - 4)
          : uidTail.padLeft(4, '0');
      final maxBaseLen = UsernameUtils.maxLength - (tail.length + 1);
      final trimmedBase = base.length > maxBaseLen
          ? base.substring(0, maxBaseLen.clamp(1, base.length))
          : base;
      final fallbackCandidate = '${trimmedBase}_$tail';

      try {
        await _reserveAndWriteUsername(
          authUid: authUid,
          candidateLower: fallbackCandidate,
          candidateDisplay: fallbackCandidate,
          previousLower: '',
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[UserProfileRepository] ensureUsernameIfMissing: final '
            'fallback attempt failed for $authUid: $e',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[UserProfileRepository] ensureUsernameIfMissing error: $e',
        );
      }
      // Never throw from here — this is a best-effort background
      // migration/generation step, not a user-initiated action.
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

      // Best-effort: assign a username right away for brand-new
      // profiles. Failure here must never block onboarding — if it
      // fails (offline, etc.) the Profile screen's own
      // ensureUsernameIfMissing() call will retry on next load.
      try {
        await ensureUsernameIfMissing();
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[UserProfileRepository] createIfMissing: initial username '
            'assignment failed for $targetUid (non-fatal): $e',
          );
        }
      }
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
      await ensureUsernameIfMissing();
    } catch (_) {}
  }
}
