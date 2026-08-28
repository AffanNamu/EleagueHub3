// lib/features/auth/data/user_profile_repository.dart

import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';

import '../../master_leagues/domain/master_league_plan.dart';
import '../../search/data/user_search_repository.dart';
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
        if (plan == MasterLeaguePlan.pro || plan == MasterLeaguePlan.elite)
          'isPremium': true,
        if (plan == MasterLeaguePlan.pro || plan == MasterLeaguePlan.elite)
          'premiumExpiresAtMs': expiresAtMs,
      };

      await _writeUserDocWithRetry(authUid, payload);

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
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

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

    await _firestore.runTransaction((txn) async {
      final newSnap = await txn.get(newRef);
      if (newSnap.exists) {
        final owner = (newSnap.data()?['userId'] as String? ?? '').trim();
        if (owner.isNotEmpty && owner != authUid) {
          throw const UsernameUnavailableException(
            'That username is already taken.',
          );
        }
        return;
      }

      txn.set(newRef, <String, dynamic>{
        'userId': authUid,
        'createdAtMs': now,
      });
    }).timeout(const Duration(seconds: 20));

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
      try {
        final snap = await newRef.get();
        final owner = (snap.data()?['userId'] as String? ?? '').trim();
        if (snap.exists && owner == authUid) {
          await newRef.delete();
        }
      } catch (_) {}
      rethrow;
    }

    // Keep the search index in sync so this username is immediately
    // findable via UserSearchRepository.search(). Best-effort — must
    // never block or fail the username save itself.
    unawaited(UserSearchRepository().syncUsername(candidateLower));

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
          continue;
        }
      }

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
