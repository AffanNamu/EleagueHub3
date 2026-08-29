//lib/features/profile/data/team_profile_repository.dart
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/country/country_resolver_service.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../search/data/user_search_repository.dart';
import '../models/recent_match.dart';
import '../models/squad.dart';
import '../models/team_profile.dart';
import '../models/trophy.dart';
import '../models/user_stats.dart';

class TeamProfileRepositoryException implements Exception {
  final String message;
  const TeamProfileRepositoryException(this.message);

  @override
  String toString() => message;
}

class TeamProfileRepository {
  TeamProfileRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  String _requireAuthUid() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const TeamProfileRepositoryException('Please sign in and try again.');
    }
    return uid;
  }

  Never _rethrowFriendly(Object e) {
    if (e is TeamProfileRepositoryException) throw e;
    if (e is SocketException) {
      throw const TeamProfileRepositoryException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    }
    if (e is TimeoutException) {
      throw const TeamProfileRepositoryException(
        'Your internet connection seems unstable. Please try again.',
      );
    }
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          throw const TeamProfileRepositoryException(
            'You do not have permission to do that.',
          );
        case 'unavailable':
        case 'deadline-exceeded':
          throw const TeamProfileRepositoryException(
            'Your network appears to be offline. Please check your connection and try again.',
          );
        default:
          throw const TeamProfileRepositoryException(
            "We couldn't complete this action. Please try again.",
          );
      }
    }
    throw const TeamProfileRepositoryException('Something went wrong. Please try again.');
  }

  // ── Team profile ────────────────────────────────────────────────────────

  Future<TeamProfile> fetchTeamProfile(String userId) async {
    try {
      final uid = userId.trim();
      if (uid.isEmpty) return TeamProfile.empty('');

      final doc = await _users
          .doc(uid)
          .collection('team_profile')
          .doc('profile')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      if (!doc.exists) return TeamProfile.empty(uid);
      return TeamProfile.fromMap(uid, doc.data() ?? {});
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Stream<TeamProfile> watchTeamProfile(String userId) {
    final uid = userId.trim();
    if (uid.isEmpty) return Stream.value(TeamProfile.empty(''));

    return _users
        .doc(uid)
        .collection('team_profile')
        .doc('profile')
        .snapshots()
        .map((doc) =>
            doc.exists ? TeamProfile.fromMap(uid, doc.data() ?? {}) : TeamProfile.empty(uid));
  }

  Future<void> saveTeamProfile(TeamProfile profile) async {
    try {
      final authUid = _requireAuthUid();
      if (profile.userId.trim() != authUid) {
        throw const TeamProfileRepositoryException(
          'You can only edit your own team profile.',
        );
      }

      await _users
          .doc(authUid)
          .collection('team_profile')
          .doc('profile')
          .set(profile.toMap(), SetOptions(merge: true))
          .timeout(const Duration(seconds: 15));

      final account = await UserProfileRepository().fetchByUserId(authUid);

      // Resolve country alongside the existing resync so every team-profile
      // save also keeps "Teams Near You" eligibility up to date — this is
      // in addition to (not instead of) the background backfill that
      // covers users who never touch their team profile at all (see
      // UserSearchRepository.backfillCountryIfMissing(), called from the
      // Profile screen).
      String? country;
      try {
        country = await CountryResolverService.instance.resolveCountryCode();
      } catch (_) {
        country = null;
      }

      unawaited(UserSearchRepository().syncSelfIndex(
        displayName: account?.displayName ?? '',
        shareId: account?.effectiveShareId ?? '',
        game: profile.game,
        badge: '',
        avatarUrl: account?.effectivePhotoUrl ?? '',
        country: country,
      ));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Updates ONLY the cover/background image for the CURRENTLY signed-in
  /// user's own team profile (Feature 1 — Profile Background).
  ///
  /// Fetches the existing [TeamProfile] first (rather than writing a
  /// partial document) because the `team_profile/profile` Firestore rule
  /// validates every field on `request.resource.data` directly (game,
  /// favoriteClub, favoritePlayer, bio, bannerImageUrl, themeColor,
  /// visibility, updatedAtMs) — a write missing any of those fields would
  /// be rejected. Delegates to [saveTeamProfile] so ownership enforcement
  /// and the search-index sync stay in exactly one place.
  ///
  /// Pass an empty string to clear the cover image back to the default
  /// gradient fallback.
  Future<void> updateBannerImage({required String bannerImageUrl}) async {
    try {
      final authUid = _requireAuthUid();
      final current = await fetchTeamProfile(authUid);
      final updated = current.copyWith(bannerImageUrl: bannerImageUrl.trim());
      await saveTeamProfile(updated);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  // ── Squads ───────────────────────────────────────────────────────────────

  Future<Squad> fetchSquad({required String userId, required String gameId}) async {
    try {
      final uid = userId.trim();
      final doc = await _users
          .doc(uid)
          .collection('squads')
          .doc(gameId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      if (!doc.exists) return Squad.empty(gameId);
      return Squad.fromDoc(doc);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Stream<Squad> watchSquad({required String userId, required String gameId}) {
    final uid = userId.trim();
    return _users
        .doc(uid)
        .collection('squads')
        .doc(gameId)
        .snapshots()
        .map((doc) => doc.exists ? Squad.fromDoc(doc) : Squad.empty(gameId));
  }

  Future<List<String>> fetchSquadGameIds(String userId) async {
    try {
      final uid = userId.trim();
      final snap = await _users
          .doc(uid)
          .collection('squads')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      return snap.docs.map((d) => d.id).toList(growable: false);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> saveSquad(Squad squad) async {
    try {
      final authUid = _requireAuthUid();
      await _users
          .doc(authUid)
          .collection('squads')
          .doc(squad.gameId)
          .set(squad.toMap(), SetOptions(merge: true))
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// NEW: updates ONLY the real squad/team photo for [gameId], for the
  /// currently signed-in user. Fetches the existing [Squad] first
  /// (rather than writing a partial document) for the same reason
  /// [updateBannerImage] does above -- avoids clobbering the rest of
  /// the squad doc, and stays consistent even if this squad's Firestore
  /// rule ever validates the full document shape. Pass an empty string
  /// to remove the photo.
  Future<void> updateSquadPhoto({
    required String gameId,
    required String squadPhotoUrl,
  }) async {
    try {
      final authUid = _requireAuthUid();
      final current = await fetchSquad(userId: authUid, gameId: gameId);
      final updated = current.withSquadPhoto(squadPhotoUrl.trim());
      await saveSquad(updated);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  // ── Trophies ─────────────────────────────────────────────────────────────

  Stream<List<Trophy>> watchTrophies(String userId) {
    final uid = userId.trim();
    return _users
        .doc(uid)
        .collection('trophies')
        .orderBy('createdAtMs', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Trophy.fromDoc).toList(growable: false));
  }

  // ── Stats (cached aggregate) ────────────────────────────────────────────

  Future<UserStats> fetchStats(String userId) async {
    try {
      final uid = userId.trim();
      final doc = await _users
          .doc(uid)
          .collection('stats')
          .doc('summary')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      if (!doc.exists) return UserStats.empty();
      return UserStats.fromDoc(doc);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Stream<UserStats> watchStats(String userId) {
    final uid = userId.trim();
    return _users
        .doc(uid)
        .collection('stats')
        .doc('summary')
        .snapshots()
        .map((doc) => doc.exists ? UserStats.fromDoc(doc) : UserStats.empty());
  }

  // ── Recent matches ──────────────────────────────────────────────────────

  Stream<List<RecentMatch>> watchRecentMatches(String userId, {int limit = 15}) {
    final uid = userId.trim();
    return _users
        .doc(uid)
        .collection('recent_matches')
        .orderBy('playedAtMs', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(RecentMatch.fromDoc).toList(growable: false));
  }

  // ── Follow / unfollow ────────────────────────────────────────────────────

  Future<bool> isFollowing(String targetUserId) async {
    try {
      final authUid = _requireAuthUid();
      final doc = await _users
          .doc(targetUserId.trim())
          .collection('followers')
          .doc(authUid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));

      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  Future<void> follow(String targetUserId) async {
    try {
      final authUid = _requireAuthUid();
      final target = targetUserId.trim();
      if (target.isEmpty || target == authUid) {
        throw const TeamProfileRepositoryException('Invalid target user.');
      }

      final followerRef = _users.doc(target).collection('followers').doc(authUid);
      final followingRef = _users.doc(authUid).collection('following').doc(target);
      final targetStatsRef = _users.doc(target).collection('stats').doc('summary');
      final selfStatsRef = _users.doc(authUid).collection('stats').doc('summary');

      final now = DateTime.now().millisecondsSinceEpoch;

      await _firestore.runTransaction((txn) async {
        final existing = await txn.get(followerRef);
        if (existing.exists) return;

        txn.set(followerRef, {'userId': authUid, 'followedAtMs': now});
        txn.set(followingRef, {'userId': target, 'followedAtMs': now});

        final targetStatsSnap = await txn.get(targetStatsRef);
        final targetFollowers =
            ((targetStatsSnap.data() ?? {})['followersCount'] as num?)?.toInt() ?? 0;
        txn.set(
          targetStatsRef,
          {'followersCount': targetFollowers + 1},
          SetOptions(merge: true),
        );

        final selfStatsSnap = await txn.get(selfStatsRef);
        final selfFollowing =
            ((selfStatsSnap.data() ?? {})['followingCount'] as num?)?.toInt() ?? 0;
        txn.set(
          selfStatsRef,
          {'followingCount': selfFollowing + 1},
          SetOptions(merge: true),
        );
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> unfollow(String targetUserId) async {
    try {
      final authUid = _requireAuthUid();
      final target = targetUserId.trim();

      final followerRef = _users.doc(target).collection('followers').doc(authUid);
      final followingRef = _users.doc(authUid).collection('following').doc(target);
      final targetStatsRef = _users.doc(target).collection('stats').doc('summary');
      final selfStatsRef = _users.doc(authUid).collection('stats').doc('summary');

      await _firestore.runTransaction((txn) async {
        final existing = await txn.get(followerRef);
        if (!existing.exists) return;

        txn.delete(followerRef);
        txn.delete(followingRef);

        final targetStatsSnap = await txn.get(targetStatsRef);
        final targetFollowers =
            ((targetStatsSnap.data() ?? {})['followersCount'] as num?)?.toInt() ?? 0;
        txn.set(
          targetStatsRef,
          {'followersCount': (targetFollowers - 1).clamp(0, 1 << 31)},
          SetOptions(merge: true),
        );

        final selfStatsSnap = await txn.get(selfStatsRef);
        final selfFollowing =
            ((selfStatsSnap.data() ?? {})['followingCount'] as num?)?.toInt() ?? 0;
        txn.set(
          selfStatsRef,
          {'followingCount': (selfFollowing - 1).clamp(0, 1 << 31)},
          SetOptions(merge: true),
        );
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  // ── Block ────────────────────────────────────────────────────────────────

  Future<void> blockUser(String targetUserId) async {
    try {
      final authUid = _requireAuthUid();
      final target = targetUserId.trim();
      if (target.isEmpty || target == authUid) {
        throw const TeamProfileRepositoryException('Invalid target user.');
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final batch = _firestore.batch();

      batch.set(
        _users.doc(authUid).collection('blocked_users').doc(target),
        {'userId': target, 'blockedAtMs': now},
      );

      batch.set(
        _users.doc(target).collection('blocked_by').doc(authUid),
        {'userId': authUid, 'blockedAtMs': now},
      );

      await batch.commit().timeout(const Duration(seconds: 15));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> unblockUser(String targetUserId) async {
    try {
      final authUid = _requireAuthUid();
      final target = targetUserId.trim();

      final batch = _firestore.batch();
      batch.delete(_users.doc(authUid).collection('blocked_users').doc(target));
      batch.delete(_users.doc(target).collection('blocked_by').doc(authUid));

      await batch.commit().timeout(const Duration(seconds: 15));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<bool> isBlocked(String targetUserId) async {
    try {
      final authUid = _requireAuthUid();
      final doc = await _users
          .doc(authUid)
          .collection('blocked_users')
          .doc(targetUserId.trim())
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));

      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isBlockedEitherWay(String targetUserId) async {
    try {
      final authUid = _requireAuthUid();
      final target = targetUserId.trim();
      if (target.isEmpty) return false;

      final results = await Future.wait([
        _users
            .doc(authUid)
            .collection('blocked_users')
            .doc(target)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10)),
        _users
            .doc(authUid)
            .collection('blocked_by')
            .doc(target)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10)),
      ]);

      return results.any((doc) => doc.exists);
    } catch (_) {
      return false;
    }
  }
}
