import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../models/fixture_match.dart';
import '../models/knockout_match.dart';
import '../models/league.dart';
import '../models/membership.dart';
import '../models/team.dart';

enum LeagueJoinMode { participant, viewer }

class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

class LocalLeaguesRepository {
  LocalLeaguesRepository(this._prefs);

  // ignore: unused_field
  final PreferencesService _prefs;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  static const String kLeaguesKey = 'local_leagues';
  static const String kMembershipsKey = 'local_memberships';
  static const String kTeamsKey = 'local_teams';
  static const String kMatchesKey = 'local_matches';
  static const String kKnockoutMatchesKey = 'local_knockout_matches';

  String _requireAuthUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const UserFriendlyException('Please sign in and try again.');
    }
    return uid;
  }

  Future<void> _requireOnline() async {
    await ConnectivityService.instance.requireOnline(
      timeout: const Duration(seconds: 4),
    );
  }

  bool _isNetworkFirebaseException(FirebaseException e) {
    return e.code == 'unavailable' || e.code == 'deadline-exceeded';
  }

  Never _rethrowFriendly(Object e) {
    if (e is UserFriendlyException) throw e;

    if (e is SocketException || e is HandshakeException) {
      throw const UserFriendlyException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    }

    if (e is TimeoutException) {
      throw const UserFriendlyException(
        'Your internet connection seems unstable. Please try again.',
      );
    }

    if (e is FirebaseAuthException) {
      if (e.code == 'network-request-failed') {
        throw const UserFriendlyException(
          'Your network appears to be offline. Please check your connection and try again.',
        );
      }
      if (e.code == 'unauthenticated') {
        throw const UserFriendlyException('Please sign in and try again.');
      }
      throw const UserFriendlyException(
        "We couldn't complete this action. Please try again.",
      );
    }

    if (e is FirebaseException) {
      if (_isNetworkFirebaseException(e)) {
        throw const UserFriendlyException(
          'Your network appears to be offline. Please check your connection and try again.',
        );
      }
      if (e.code == 'permission-denied') {
        throw const UserFriendlyException(
          'You don\u2019t have permission to do that right now.',
        );
      }
      if (e.code == 'unauthenticated') {
        throw const UserFriendlyException('Please sign in and try again.');
      }
      throw const UserFriendlyException(
        "We couldn't complete this action. Please try again.",
      );
    }

    throw const UserFriendlyException('Something went wrong. Please try again.');
  }

  bool _looksLikeFirebaseUid(String s) => s.trim().length > 20;

  // ================================================================
  // ONE-TIME SILENT MIGRATION
  //
  // Called automatically by getLeagueById() and getAllLeagues().
  //
  // Problem: old leagues created with the offline-sync version stored
  // organizerUserId as a short shareId (e.g. "eSa0JDUe", 8 chars).
  // The Firestore security rules check organizerUid (Firebase UID).
  // Old leagues have no organizerUid field → isOwner() returns false
  // → PERMISSION DENIED on saveTeams, deleteLeague, etc.
  //
  // Fix: when the current auth user IS the organizer (detected via
  // memberIds + memberships role=0), silently write organizerUid,
  // ownerUid, ownerId to the league doc using the league's own
  // "allow update" rule which permits memberIds writes by members.
  //
  // This runs once per league per session. After it runs, all
  // subsequent isOwner() checks pass normally.
  // ================================================================
  Future<void> _silentlyPatchOrganizerUidIfNeeded({
    required String leagueId,
    required Map<String, dynamic> leagueData,
    required String authUid,
  }) async {
    try {
      // Already has a valid Firebase UID in organizerUid — nothing to do.
      final existing = (leagueData['organizerUid'] as String? ?? '').trim();
      if (_looksLikeFirebaseUid(existing)) return;

      // Check if current user is in memberIds.
      final memberIds = leagueData['memberIds'];
      final isInMemberIds =
          memberIds is List && memberIds.contains(authUid);
      if (!isInMemberIds) return;

      // Check if current user has role=0 (organizer) in memberships.
      // This is the authoritative organizer check without needing
      // organizerUid to already be set.
      final membershipDoc = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('memberships')
          .doc(authUid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      if (!membershipDoc.exists) return;

      final role =
          (membershipDoc.data()?['role'] as num?)?.toInt() ?? -1;

      // role == 0 means organizer
      if (role != 0) return;

      // Current user IS the organizer. Patch the league doc.
      // The league "allow update" rule permits any member to write
      // memberIds — we piggyback organizerUid on the same write.
      // This works because the update rule is:
      //   isOwnerDirect() || (signedIn() && memberIds contains uid)
      // We satisfy the second branch.
      await _firestore
          .collection('leagues')
          .doc(leagueId)
          .set(
            {
              'organizerUid': authUid,
              'ownerUid': authUid,
              'ownerId': authUid,
              'memberIds': FieldValue.arrayUnion([authUid]),
              'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
            },
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Non-fatal: if the patch fails for any reason, we just skip it.
      // The user will see permission denied on protected actions and
      // can try again next session.
    }
  }

  String _generateJoinCode({int length = 6}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)])
        .join();
  }

  Future<String> _generateUniqueJoinCode() async {
    for (var i = 0; i < 6; i++) {
      final code = _generateJoinCode();
      final snap = await _firestore
          .collection('leagues')
          .where('code', isEqualTo: code)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      if (snap.docs.isEmpty) return code;
    }
    throw const UserFriendlyException(
      "We couldn't create a join code. Please try again.",
    );
  }

  League _docToLeague(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data =
        (doc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    final map = <String, dynamic>{...data};
    map['id'] =
        (map['id'] is String && (map['id'] as String).trim().isNotEmpty)
            ? map['id']
            : doc.id;
    return League.fromRemoteMap(map);
  }

  String _bestUserImageUrlFromUserDoc(Map<String, dynamic> data) {
    final teamImageUrl =
        (data['teamImageUrl'] as String?)?.trim() ?? '';
    if (teamImageUrl.isNotEmpty) return teamImageUrl;

    final profileImageUrl =
        (data['profileImageUrl'] as String?)?.trim() ?? '';
    if (profileImageUrl.isNotEmpty) return profileImageUrl;

    final photoUrl = (data['photoUrl'] as String?)?.trim() ?? '';
    if (photoUrl.isNotEmpty) return photoUrl;

    return '';
  }

  Future<Map<String, String>> _loadUserImageUrlsByUids(
    List<String> uids,
  ) async {
    final ids = uids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return const <String, String>{};

    final out = <String, String>{};

    const chunkSize = 10;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(
        i,
        (i + chunkSize > ids.length) ? ids.length : i + chunkSize,
      );

      final snap = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));

      for (final d in snap.docs) {
        final data = d.data();
        final url = _bestUserImageUrlFromUserDoc(data);
        if (url.trim().isNotEmpty) {
          out[d.id] = url.trim();
        }
      }
    }

    return out;
  }

  Future<List<League>> listLeagues() => getAllLeagues();

  Future<List<League>> getAllLeagues() async {
    try {
      final authUid = _requireAuthUid();
      await _requireOnline();

      final snapshot = await _firestore
          .collection('leagues')
          .where('memberIds', arrayContains: authUid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      final leagues = snapshot.docs
          .map((d) => _docToLeague(d))
          .toList(growable: false);

      // Silently patch any league where current user is organizer
      // but organizerUid is missing (legacy offline-sync data).
      for (final doc in snapshot.docs) {
        final data = doc.data();
        // Fire-and-forget: do not await, do not block list loading.
        _silentlyPatchOrganizerUidIfNeeded(
          leagueId: doc.id,
          leagueData: data,
          authUid: authUid,
        );
      }

      return leagues;
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<League?> getLeagueById(String id) async {
    try {
      final authUid = _requireAuthUid();
      await _requireOnline();

      final doc = await _firestore
          .collection('leagues')
          .doc(id)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      if (!doc.exists) return null;

      final data = doc.data() ?? <String, dynamic>{};

      // Silently patch organizerUid if missing and current user is organizer.
      // Await here so the patch completes before the caller tries to
      // use the league (e.g. saveTeams). This is the key difference from
      // getAllLeagues where we fire-and-forget.
      await _silentlyPatchOrganizerUidIfNeeded(
        leagueId: id,
        leagueData: data,
        authUid: authUid,
      );

      return _docToLeague(doc);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> saveLeague(League league) async {
    try {
      final authUid = _requireAuthUid();
      await _requireOnline();

      final leagueId =
          league.id.trim().isEmpty ? _uuid.v4() : league.id.trim();
      final fixedCode = league.code.trim().isNotEmpty
          ? league.code.trim().toUpperCase()
          : await _generateUniqueJoinCode();

      final fixed = league.copyWith(
        id: leagueId,
        organizerUid: authUid,
        code: fixedCode,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      final leagueRef =
          _firestore.collection('leagues').doc(leagueId);
      final organizerMembershipRef =
          leagueRef.collection('memberships').doc(authUid);

      final now = DateTime.now().millisecondsSinceEpoch;

      final batch = _firestore.batch();

      batch.set(
        leagueRef,
        {
          ...fixed.toJson(),
          'organizerUid': authUid,
          'ownerUid': authUid,
          'ownerId': authUid,
          'isPrivate': fixed.isPrivate,
          'memberIds': FieldValue.arrayUnion([authUid]),
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      );

      final membership = Membership(
        id: authUid,
        leagueId: leagueId,
        userId: authUid,
        teamId: null,
        role: LeagueRole.organizer,
        updatedAtMs: now,
        version: 1,
      );

      batch.set(
        organizerMembershipRef,
        membership.toRemoteMap(),
        SetOptions(merge: true),
      );

      await batch.commit().timeout(const Duration(seconds: 25));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> deleteLeagueCompletely(String leagueId) async {
    try {
      _requireAuthUid();
      await _requireOnline();

      final leagueRef =
          _firestore.collection('leagues').doc(leagueId);

      Future<void> deleteAllDocsIn(String sub) async {
        final col = leagueRef.collection(sub);
        final snap = await col
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 30));
        if (snap.docs.isEmpty) return;

        const chunkSize = 450;
        for (var i = 0; i < snap.docs.length; i += chunkSize) {
          final batch = _firestore.batch();
          final chunk = snap.docs.sublist(
            i,
            (i + chunkSize > snap.docs.length)
                ? snap.docs.length
                : i + chunkSize,
          );
          for (final d in chunk) {
            batch.delete(d.reference);
          }
          await batch.commit().timeout(const Duration(seconds: 30));
        }
      }

      await deleteAllDocsIn('teams');
      await deleteAllDocsIn('matches');
      await deleteAllDocsIn('knockout');
      await deleteAllDocsIn('memberships');
      await deleteAllDocsIn('announcements');
      await deleteAllDocsIn('space');

      await leagueRef
          .delete()
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<League> createLeagueLocally({
    required League league,
    required String organizerUserId,
  }) async {
    try {
      final authUid = _requireAuthUid();
      await _requireOnline();

      final now = DateTime.now().millisecondsSinceEpoch;
      final leagueId =
          league.id.trim().isEmpty ? _uuid.v4() : league.id.trim();
      final code = league.code.trim().isNotEmpty
          ? league.code.trim().toUpperCase()
          : await _generateUniqueJoinCode();

      final stored = league.copyWith(
        id: leagueId,
        organizerUid: authUid,
        organizerUserId: organizerUserId,
        code: code,
        updatedAtMs: now,
      );

      final leagueRef =
          _firestore.collection('leagues').doc(leagueId);
      final organizerMembershipRef =
          leagueRef.collection('memberships').doc(authUid);

      final batch = _firestore.batch();

      batch.set(
        leagueRef,
        {
          ...stored.toJson(),
          'organizerUid': authUid,
          'ownerUid': authUid,
          'ownerId': authUid,
          'isPrivate': stored.isPrivate,
          'memberIds': FieldValue.arrayUnion([authUid]),
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      );

      final membership = Membership(
        id: authUid,
        leagueId: leagueId,
        userId: authUid,
        teamId: null,
        role: LeagueRole.organizer,
        updatedAtMs: now,
        version: 1,
      );

      batch.set(
        organizerMembershipRef,
        membership.toRemoteMap(),
        SetOptions(merge: true),
      );

      await batch.commit().timeout(const Duration(seconds: 25));

      return stored;
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<League> joinLeagueLocallyByCode({
    required String joinCode,
    required String userId,
    required League Function(String generatedLeagueId) placeholderBuilder,
    LeagueJoinMode mode = LeagueJoinMode.participant,
  }) async {
    try {
      final authUid = _requireAuthUid();
      await _requireOnline();

      final code = joinCode.trim().toUpperCase();
      if (code.isEmpty) {
        throw const UserFriendlyException(
          'Please enter a valid league code.',
        );
      }

      final query = await _firestore
          .collection('leagues')
          .where('code', isEqualTo: code)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      if (query.docs.isEmpty) {
        throw const UserFriendlyException(
          "We couldn't find a league with that code.",
        );
      }

      final leagueDoc = query.docs.first;
      final leagueId = leagueDoc.id;

      final leagueRef =
          _firestore.collection('leagues').doc(leagueId);

      // Step 1: add self to memberIds
      await leagueRef
          .set(
            {
              'memberIds': FieldValue.arrayUnion([authUid]),
              'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
            },
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 20));

      // Step 2: create membership doc (standalone write, not transaction)
      if (mode == LeagueJoinMode.participant) {
        final membershipRef =
            leagueRef.collection('memberships').doc(authUid);

        final existing = await membershipRef
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 12));

        final existingRoleIdx =
            (existing.data()?['role'] as num?)?.toInt();
        final existingRole = (existingRoleIdx != null &&
                existingRoleIdx >= 0 &&
                existingRoleIdx < LeagueRole.values.length)
            ? LeagueRole.values[existingRoleIdx]
            : null;

        if (!existing.exists ||
            existingRole == null ||
            existingRole == LeagueRole.member) {
          final now = DateTime.now().millisecondsSinceEpoch;

          final membership = Membership(
            id: authUid,
            leagueId: leagueId,
            userId: authUid,
            teamId: null,
            role: LeagueRole.member,
            updatedAtMs: now,
            version: 1,
          );

          await membershipRef
              .set(membership.toRemoteMap(), SetOptions(merge: true))
              .timeout(const Duration(seconds: 20));
        }
      }

      final fresh = await leagueRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      return _docToLeague(fresh);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<List<Membership>> listMemberships() async {
    try {
      final authUid = _requireAuthUid();
      await _requireOnline();

      final leaguesSnap = await _firestore
          .collection('leagues')
          .where('memberIds', arrayContains: authUid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      final leagueIds =
          leaguesSnap.docs.map((d) => d.id).toList(growable: false);
      if (leagueIds.isEmpty) return const <Membership>[];

      final all = await Future.wait(
        leagueIds.map((leagueId) async {
          final snap = await _firestore
              .collection('leagues')
              .doc(leagueId)
              .collection('memberships')
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 20));

          return snap.docs.map((d) {
            final map = <String, dynamic>{...d.data()};
            map['id'] =
                (map['id'] is String &&
                        (map['id'] as String).trim().isNotEmpty)
                    ? map['id']
                    : d.id;
            map['leagueId'] =
                (map['leagueId'] as String?) ?? leagueId;
            map['userId'] = (map['userId'] as String?) ?? '';
            map['role'] = (map['role'] as num?)?.toInt() ??
                LeagueRole.member.index;
            map['updatedAtMs'] =
                (map['updatedAtMs'] as num?)?.toInt() ??
                    DateTime.now().millisecondsSinceEpoch;
            map['version'] =
                (map['version'] as num?)?.toInt() ?? 1;
            return Membership.fromRemoteMap(map);
          }).toList();
        }),
      );

      return all.expand((x) => x).toList(growable: false);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<Membership?> getMembership({
    required String leagueId,
    required String userId,
  }) async {
    try {
      _requireAuthUid();
      await _requireOnline();

      final uid = userId.trim();
      if (uid.isEmpty) return null;

      final direct = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('memberships')
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));

      if (direct.exists) {
        final map = <String, dynamic>{
          ...(direct.data() ?? <String, dynamic>{}),
        };
        map['id'] =
            (map['id'] is String &&
                    (map['id'] as String).trim().isNotEmpty)
                ? map['id']
                : direct.id;
        map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
        map['userId'] = (map['userId'] as String?) ?? uid;
        map['role'] =
            (map['role'] as num?)?.toInt() ?? LeagueRole.member.index;
        map['updatedAtMs'] = (map['updatedAtMs'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;
        map['version'] = (map['version'] as num?)?.toInt() ?? 1;
        return Membership.fromRemoteMap(map);
      }

      final snap = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('memberships')
          .where('userId', isEqualTo: uid)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      if (snap.docs.isEmpty) return null;

      final doc = snap.docs.first;
      final map = <String, dynamic>{...doc.data()};
      map['id'] =
          (map['id'] is String &&
                  (map['id'] as String).trim().isNotEmpty)
              ? map['id']
              : doc.id;
      map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
      map['userId'] = (map['userId'] as String?) ?? uid;
      map['role'] =
          (map['role'] as num?)?.toInt() ?? LeagueRole.member.index;
      map['updatedAtMs'] = (map['updatedAtMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;
      map['version'] = (map['version'] as num?)?.toInt() ?? 1;
      return Membership.fromRemoteMap(map);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> assignTeamToUserInLeague({
    required String leagueId,
    required String userId,
    required String teamId,
  }) async {
    try {
      _requireAuthUid();
      await _requireOnline();

      final uid = userId.trim();
      if (uid.isEmpty) {
        throw const UserFriendlyException(
          'Please select a valid user.',
        );
      }

      final membershipRef = _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('memberships')
          .doc(uid);

      final now = DateTime.now().millisecondsSinceEpoch;
      final existing = await membershipRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));

      if (!existing.exists) {
        final membership = Membership(
          id: uid,
          leagueId: leagueId,
          userId: uid,
          teamId: teamId,
          role: LeagueRole.member,
          updatedAtMs: now,
          version: 1,
        );

        await membershipRef
            .set(membership.toRemoteMap(), SetOptions(merge: true))
            .timeout(const Duration(seconds: 20));
        return;
      }

      final data = existing.data() ?? <String, dynamic>{};
      final currentVersion =
          (data['version'] as num?)?.toInt() ?? 1;

      await membershipRef
          .set(
            {
              'teamId': teamId,
              'updatedAtMs': now,
              'version': currentVersion + 1,
            },
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<List<Team>> getTeams(String leagueId) async {
    try {
      _requireAuthUid();
      await _requireOnline();

      final snap = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('teams')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      final baseTeams = snap.docs.map((d) {
        final map = <String, dynamic>{...d.data()};
        map['id'] =
            (map['id'] is String &&
                    (map['id'] as String).trim().isNotEmpty)
                ? map['id']
                : d.id;
        map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
        return Team.fromRemoteMap(map);
      }).toList(growable: false);

      final uidTeamIds = baseTeams
          .map((t) => t.id.trim())
          .where((id) => _looksLikeFirebaseUid(id))
          .toList(growable: false);

      if (uidTeamIds.isEmpty) return baseTeams;

      final userImages = await _loadUserImageUrlsByUids(uidTeamIds);

      if (userImages.isEmpty) return baseTeams;

      return baseTeams.map((t) {
        final override = userImages[t.id.trim()];
        if (override != null && override.trim().isNotEmpty) {
          return t.copyWith(teamImageUrl: override.trim());
        }
        return t;
      }).toList(growable: false);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> saveTeams(String leagueId, List<Team> allTeams) async {
    try {
      final authUid = _requireAuthUid();
      await _requireOnline();

      final col = _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('teams');

      final existing = await col
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      const chunkSize = 450;

      if (existing.docs.isNotEmpty) {
        for (var i = 0; i < existing.docs.length; i += chunkSize) {
          final batch = _firestore.batch();
          final chunk = existing.docs.sublist(
            i,
            (i + chunkSize > existing.docs.length)
                ? existing.docs.length
                : i + chunkSize,
          );
          for (final d in chunk) {
            batch.delete(d.reference);
          }
          await batch.commit().timeout(const Duration(seconds: 30));
        }
      }

      for (var i = 0; i < allTeams.length; i += chunkSize) {
        final batch = _firestore.batch();
        final chunk = allTeams.sublist(
          i,
          (i + chunkSize > allTeams.length)
              ? allTeams.length
              : i + chunkSize,
        );
        for (final t in chunk) {
          final id =
              t.id.trim().isEmpty ? _uuid.v4() : t.id.trim();

          final inferredOwnerId =
              (t.ownerId.trim().isNotEmpty)
                  ? t.ownerId.trim()
                  : (_looksLikeFirebaseUid(id) ? id : authUid);

          final data = t
              .copyWith(
                id: id,
                leagueId: leagueId,
                ownerId: inferredOwnerId,
              )
              .toRemoteMap();

          batch.set(col.doc(id), data, SetOptions(merge: true));
        }
        await batch.commit().timeout(const Duration(seconds: 30));
      }
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<List<FixtureMatch>> getMatches(String leagueId) async {
    try {
      _requireAuthUid();
      await _requireOnline();

      final snap = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('matches')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      return snap.docs.map((d) {
        final map = <String, dynamic>{...d.data()};
        map['id'] =
            (map['id'] is String &&
                    (map['id'] as String).trim().isNotEmpty)
                ? map['id']
                : d.id;
        map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
        return FixtureMatch.fromJson(map);
      }).toList(growable: false);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> saveMatches(
    String leagueId,
    List<FixtureMatch> matches,
  ) async {
    try {
      _requireAuthUid();
      await _requireOnline();

      final col = _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('matches');

      const chunkSize = 450;
      for (var i = 0; i < matches.length; i += chunkSize) {
        final batch = _firestore.batch();
        final chunk = matches.sublist(
          i,
          (i + chunkSize > matches.length)
              ? matches.length
              : i + chunkSize,
        );
        for (final m in chunk) {
          final id =
              m.id.trim().isEmpty ? _uuid.v4() : m.id.trim();
          final data = <String, dynamic>{
            ...m.toJson(),
            'id': id,
            'leagueId': leagueId,
          };
          batch.set(col.doc(id), data, SetOptions(merge: true));
        }
        await batch.commit().timeout(const Duration(seconds: 30));
      }
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> replaceMatches(
    String leagueId,
    List<FixtureMatch> matches,
  ) async {
    try {
      _requireAuthUid();
      await _requireOnline();

      final col = _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('matches');
      final existing = await col
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      const chunkSize = 450;

      if (existing.docs.isNotEmpty) {
        for (var i = 0; i < existing.docs.length; i += chunkSize) {
          final batch = _firestore.batch();
          final chunk = existing.docs.sublist(
            i,
            (i + chunkSize > existing.docs.length)
                ? existing.docs.length
                : i + chunkSize,
          );
          for (final d in chunk) {
            batch.delete(d.reference);
          }
          await batch.commit().timeout(const Duration(seconds: 30));
        }
      }

      await saveMatches(leagueId, matches);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<List<KnockoutMatch>> getKnockoutMatches(
    String leagueId,
  ) async {
    try {
      _requireAuthUid();
      await _requireOnline();

      final snap = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('knockout')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      final list = snap.docs.map((d) {
        final map = <String, dynamic>{...d.data()};
        map['id'] =
            (map['id'] is String &&
                    (map['id'] as String).trim().isNotEmpty)
                ? map['id']
                : d.id;
        map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
        return KnockoutMatch.fromJson(map);
      }).toList(growable: false);

      const roundOrder = <String>[
        'Play-off',
        'Round of 16',
        'Quarter Finals',
        'Semi Finals',
        'Final',
        '3rd Place',
      ];

      final sorted = [...list];
      sorted.sort((a, b) {
        final ai = roundOrder.indexOf(a.roundName);
        final bi = roundOrder.indexOf(b.roundName);
        if (ai != bi) {
          if (ai == -1) return 1;
          if (bi == -1) return -1;
          return ai.compareTo(bi);
        }
        if (a.roundName == 'Play-off' && b.roundName == 'Play-off') {
          final an = (a.nextMatchId ?? '');
          final bn = (b.nextMatchId ?? '');
          final c1 = an.compareTo(bn);
          if (c1 != 0) return c1;
          final c2 =
              (a.isSecondLeg ? 1 : 0).compareTo(b.isSecondLeg ? 1 : 0);
          if (c2 != 0) return c2;
        }
        return a.id.compareTo(b.id);
      });

      return sorted;
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> saveKnockoutMatches(
    String leagueId,
    List<KnockoutMatch> matches,
  ) async {
    try {
      _requireAuthUid();
      await _requireOnline();

      final col = _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('knockout');

      final existing = await col
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      const chunkSize = 450;

      if (existing.docs.isNotEmpty) {
        for (var i = 0; i < existing.docs.length; i += chunkSize) {
          final batch = _firestore.batch();
          final chunk = existing.docs.sublist(
            i,
            (i + chunkSize > existing.docs.length)
                ? existing.docs.length
                : i + chunkSize,
          );
          for (final d in chunk) {
            batch.delete(d.reference);
          }
          await batch.commit().timeout(const Duration(seconds: 30));
        }
      }

      for (var i = 0; i < matches.length; i += chunkSize) {
        final batch = _firestore.batch();
        final chunk = matches.sublist(
          i,
          (i + chunkSize > matches.length)
              ? matches.length
              : i + chunkSize,
        );
        for (final m in chunk) {
          final id =
              m.id.trim().isNotEmpty ? m.id.trim() : _uuid.v4();
          final data =
              m.copyWith(id: id, leagueId: leagueId).toJson();
          batch.set(col.doc(id), data, SetOptions(merge: true));
        }
        await batch.commit().timeout(const Duration(seconds: 30));
      }
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }
}
