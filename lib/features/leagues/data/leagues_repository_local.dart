import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:uuid/uuid.dart';

import '../../../core/persistence/prefs_service.dart';
import '../models/fixture_match.dart';
import '../models/knockout_match.dart';
import '../models/league.dart';
import '../models/membership.dart';
import '../models/team.dart';

/// How a user joins a league from the UI.
///
/// IMPORTANT (online-only):
/// - `participant`: user is counted as a league participant (creates Membership).
/// - `viewer`: user can view the league (added to league.memberIds for access),
///   but is NOT counted as a participant (no Membership is created).
enum LeagueJoinMode { participant, viewer }

/// User-safe exception: if UI shows `$e`, it will still be a friendly message.
class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

/// Backward-compatible repository name kept to avoid widespread refactors.
///
/// ONLINE-ONLY MIGRATION:
/// - No SharedPreferences storage for leagues/teams/matches.
/// - No local queue.
/// - All reads/writes go directly to Firestore.
/// - Errors are thrown as user-friendly messages (no raw Firebase errors).
class LocalLeaguesRepository {
  LocalLeaguesRepository(this._prefs);

  // Kept only because many screens construct this repo from prefs provider.
  // Online-only: prefs must not be used for domain data.
  // ignore: unused_field
  final PreferencesService _prefs;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  // Legacy keys kept only for compatibility (no longer used).
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

  bool _isNetworkFirebaseException(FirebaseException e) {
    return e.code == 'unavailable' || e.code == 'deadline-exceeded';
  }

  Never _rethrowFriendly(Object e) {
    if (e is UserFriendlyException) throw e;

    if (e is TimeoutException) {
      throw const UserFriendlyException('Your internet connection seems unstable. Please try again.');
    }

    if (e is FirebaseException) {
      if (_isNetworkFirebaseException(e)) {
        throw const UserFriendlyException(
          'Your network appears to be offline. Please check your connection and try again.',
        );
      }
      if (e.code == 'permission-denied') {
        throw const UserFriendlyException('You don’t have permission to do that right now.');
      }
      if (e.code == 'unauthenticated') {
        throw const UserFriendlyException('Please sign in and try again.');
      }
      throw const UserFriendlyException("We couldn't complete this action. Please try again.");
    }

    throw const UserFriendlyException('Something went wrong. Please try again.');
  }

  String _generateJoinCode({int length = 6}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
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
    throw const UserFriendlyException("We couldn't create a join code. Please try again.");
  }

  League _docToLeague(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = (doc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    final map = <String, dynamic>{...data};
    map['id'] = (map['id'] is String && (map['id'] as String).trim().isNotEmpty) ? map['id'] : doc.id;
    return League.fromRemoteMap(map);
  }

  // -----------------------
  // Leagues
  // -----------------------

  Future<List<League>> listLeagues() => getAllLeagues();

  Future<List<League>> getAllLeagues() async {
    try {
      final authUid = _requireAuthUid();

      final snapshot = await _firestore
          .collection('leagues')
          .where('memberIds', arrayContains: authUid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      return snapshot.docs.map((d) => _docToLeague(d)).toList(growable: false);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<League?> getLeagueById(String id) async {
    try {
      _requireAuthUid();

      final doc = await _firestore
          .collection('leagues')
          .doc(id)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      if (!doc.exists) return null;
      return _docToLeague(doc);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> saveLeague(League league) async {
    try {
      final authUid = _requireAuthUid();

      final leagueId = league.id.trim().isEmpty ? _uuid.v4() : league.id.trim();
      final fixedCode =
          league.code.trim().isNotEmpty ? league.code.trim().toUpperCase() : await _generateUniqueJoinCode();

      final fixed = league.copyWith(
        id: leagueId,
        organizerUid: authUid,
        code: fixedCode,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      await _firestore.collection('leagues').doc(leagueId).set(
        {
          ...fixed.toJson(),
          'organizerUid': authUid,
          'ownerUid': authUid,
          'ownerId': authUid,
          'memberIds': FieldValue.arrayUnion([authUid]),
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 25));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> deleteLeagueCompletely(String leagueId) async {
    try {
      _requireAuthUid();

      final leagueRef = _firestore.collection('leagues').doc(leagueId);

      Future<void> deleteAllDocsIn(String sub) async {
        final col = leagueRef.collection(sub);
        final snap = await col.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 30));
        if (snap.docs.isEmpty) return;

        const chunkSize = 450;
        for (var i = 0; i < snap.docs.length; i += chunkSize) {
          final batch = _firestore.batch();
          final chunk = snap.docs.sublist(i, (i + chunkSize > snap.docs.length) ? snap.docs.length : i + chunkSize);
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

      await leagueRef.delete().timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  // ------------------------------------------------------
  // CREATE (online-only)
  // ------------------------------------------------------

  Future<League> createLeagueLocally({
    required League league,
    required String organizerUserId,
  }) async {
    try {
      final authUid = _requireAuthUid();

      final now = DateTime.now().millisecondsSinceEpoch;
      final leagueId = league.id.trim().isEmpty ? _uuid.v4() : league.id.trim();

      final code = league.code.trim().isNotEmpty ? league.code.trim().toUpperCase() : await _generateUniqueJoinCode();

      final stored = league.copyWith(
        id: leagueId,
        organizerUid: authUid,
        organizerUserId: organizerUserId,
        code: code,
        updatedAtMs: now,
      );

      await _firestore.collection('leagues').doc(leagueId).set(
        {
          ...stored.toJson(),
          'organizerUid': authUid,
          'ownerUid': authUid,
          'ownerId': authUid,
          'memberIds': FieldValue.arrayUnion([authUid]),
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 25));

      final membership = Membership(
        id: _uuid.v4(),
        leagueId: leagueId,
        userId: authUid,
        teamId: null,
        role: LeagueRole.organizer,
        updatedAtMs: now,
        version: 1,
      );

      await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('memberships')
          .doc(membership.id)
          .set(membership.toRemoteMap(), SetOptions(merge: true))
          .timeout(const Duration(seconds: 20));

      return stored;
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  // ------------------------------------------------------
  // JOIN by code (online-only)
  // ------------------------------------------------------

  Future<League> joinLeagueLocallyByCode({
    required String joinCode,
    required String userId, // kept for API compatibility; auth UID is authoritative
    required League Function(String generatedLeagueId) placeholderBuilder, // ignored online-only
    LeagueJoinMode mode = LeagueJoinMode.participant,
  }) async {
    try {
      final authUid = _requireAuthUid();

      final code = joinCode.trim().toUpperCase();
      if (code.isEmpty) {
        throw const UserFriendlyException('Please enter a valid league code.');
      }

      final query = await _firestore
          .collection('leagues')
          .where('code', isEqualTo: code)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      if (query.docs.isEmpty) {
        throw const UserFriendlyException("We couldn't find a league with that code.");
      }

      final leagueDoc = query.docs.first;
      final leagueId = leagueDoc.id;

      await _firestore.collection('leagues').doc(leagueId).set(
        {
          'memberIds': FieldValue.arrayUnion([authUid]),
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 20));

      if (mode == LeagueJoinMode.participant) {
        final existing = await _firestore
            .collection('leagues')
            .doc(leagueId)
            .collection('memberships')
            .where('userId', isEqualTo: authUid)
            .limit(1)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 20));

        if (existing.docs.isEmpty) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final membership = Membership(
            id: _uuid.v4(),
            leagueId: leagueId,
            userId: authUid,
            teamId: null,
            role: LeagueRole.member,
            updatedAtMs: now,
            version: 1,
          );

          await _firestore
              .collection('leagues')
              .doc(leagueId)
              .collection('memberships')
              .doc(membership.id)
              .set(membership.toRemoteMap(), SetOptions(merge: true))
              .timeout(const Duration(seconds: 20));
        }
      }

      final fresh = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      return _docToLeague(fresh);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  // ------------------------------------------------------
  // Memberships
  // ------------------------------------------------------

  Future<List<Membership>> listMemberships() async {
    try {
      final authUid = _requireAuthUid();

      final leaguesSnap = await _firestore
          .collection('leagues')
          .where('memberIds', arrayContains: authUid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      final leagueIds = leaguesSnap.docs.map((d) => d.id).toList(growable: false);
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
            map['id'] = (map['id'] is String && (map['id'] as String).trim().isNotEmpty) ? map['id'] : d.id;
            map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
            map['userId'] = (map['userId'] as String?) ?? '';
            map['role'] = (map['role'] as num?)?.toInt() ?? LeagueRole.member.index;
            map['updatedAtMs'] = (map['updatedAtMs'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
            map['version'] = (map['version'] as num?)?.toInt() ?? 1;
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

      final uid = userId.trim();
      if (uid.isEmpty) return null;

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
      map['id'] = (map['id'] is String && (map['id'] as String).trim().isNotEmpty) ? map['id'] : doc.id;
      map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
      map['userId'] = (map['userId'] as String?) ?? uid;
      map['role'] = (map['role'] as num?)?.toInt() ?? LeagueRole.member.index;
      map['updatedAtMs'] = (map['updatedAtMs'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
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

      final uid = userId.trim();
      if (uid.isEmpty) {
        throw const UserFriendlyException('Please select a valid user.');
      }

      final existing = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('memberships')
          .where('userId', isEqualTo: uid)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      final now = DateTime.now().millisecondsSinceEpoch;

      if (existing.docs.isEmpty) {
        final membership = Membership(
          id: _uuid.v4(),
          leagueId: leagueId,
          userId: uid,
          teamId: teamId,
          role: LeagueRole.member,
          updatedAtMs: now,
          version: 1,
        );

        await _firestore
            .collection('leagues')
            .doc(leagueId)
            .collection('memberships')
            .doc(membership.id)
            .set(membership.toRemoteMap(), SetOptions(merge: true))
            .timeout(const Duration(seconds: 20));

        return;
      }

      final doc = existing.docs.first;
      final data = doc.data();
      final currentVersion = (data['version'] as num?)?.toInt() ?? 1;

      await doc.reference.set(
        {
          'teamId': teamId,
          'updatedAtMs': now,
          'version': currentVersion + 1,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  // ------------------------------------------------------
  // Teams
  // ------------------------------------------------------

  Future<List<Team>> getTeams(String leagueId) async {
    try {
      _requireAuthUid();

      final snap = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('teams')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      return snap.docs.map((d) {
        final map = <String, dynamic>{...d.data()};
        map['id'] = (map['id'] is String && (map['id'] as String).trim().isNotEmpty) ? map['id'] : d.id;
        map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
        return Team.fromRemoteMap(map);
      }).toList(growable: false);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> saveTeams(String leagueId, List<Team> allTeams) async {
    try {
      _requireAuthUid();

      final col = _firestore.collection('leagues').doc(leagueId).collection('teams');

      final existing = await col.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));

      const chunkSize = 450;

      if (existing.docs.isNotEmpty) {
        for (var i = 0; i < existing.docs.length; i += chunkSize) {
          final batch = _firestore.batch();
          final chunk = existing.docs.sublist(
            i,
            (i + chunkSize > existing.docs.length) ? existing.docs.length : i + chunkSize,
          );
          for (final d in chunk) {
            batch.delete(d.reference);
          }
          await batch.commit().timeout(const Duration(seconds: 30));
        }
      }

      for (var i = 0; i < allTeams.length; i += chunkSize) {
        final batch = _firestore.batch();
        final chunk = allTeams.sublist(i, (i + chunkSize > allTeams.length) ? allTeams.length : i + chunkSize);
        for (final t in chunk) {
          final id = t.id.trim().isEmpty ? _uuid.v4() : t.id.trim();
          final data = t.copyWith(id: id, leagueId: leagueId).toRemoteMap();
          batch.set(col.doc(id), data, SetOptions(merge: true));
        }
        await batch.commit().timeout(const Duration(seconds: 30));
      }
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  // ------------------------------------------------------
  // Matches / Fixtures
  // ------------------------------------------------------

  Future<List<FixtureMatch>> getMatches(String leagueId) async {
    try {
      _requireAuthUid();

      final snap = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('matches')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      return snap.docs.map((d) {
        final map = <String, dynamic>{...d.data()};
        map['id'] = (map['id'] is String && (map['id'] as String).trim().isNotEmpty) ? map['id'] : d.id;
        map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
        return FixtureMatch.fromJson(map);
      }).toList(growable: false);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> saveMatches(String leagueId, List<FixtureMatch> matches) async {
    try {
      _requireAuthUid();

      final col = _firestore.collection('leagues').doc(leagueId).collection('matches');

      const chunkSize = 450;
      for (var i = 0; i < matches.length; i += chunkSize) {
        final batch = _firestore.batch();
        final chunk = matches.sublist(i, (i + chunkSize > matches.length) ? matches.length : i + chunkSize);
        for (final m in chunk) {
          final id = m.id.trim().isEmpty ? _uuid.v4() : m.id.trim();

          // IMPORTANT:
          // FixtureMatch.copyWith in your codebase does NOT reliably expose `id`.
          // So we write JSON then override identifiers explicitly to avoid build breaks.
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

  Future<void> replaceMatches(String leagueId, List<FixtureMatch> matches) async {
    try {
      _requireAuthUid();

      final col = _firestore.collection('leagues').doc(leagueId).collection('matches');
      final existing = await col.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));

      const chunkSize = 450;

      if (existing.docs.isNotEmpty) {
        for (var i = 0; i < existing.docs.length; i += chunkSize) {
          final batch = _firestore.batch();
          final chunk = existing.docs.sublist(
            i,
            (i + chunkSize > existing.docs.length) ? existing.docs.length : i + chunkSize,
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

  // ------------------------------------------------------
  // Knockout matches
  // ------------------------------------------------------

  Future<List<KnockoutMatch>> getKnockoutMatches(String leagueId) async {
    try {
      _requireAuthUid();

      final snap = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('knockout')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      final list = snap.docs.map((d) {
        final map = <String, dynamic>{...d.data()};
        map['id'] = (map['id'] is String && (map['id'] as String).trim().isNotEmpty) ? map['id'] : d.id;
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

          final c2 = (a.isSecondLeg ? 1 : 0).compareTo(b.isSecondLeg ? 1 : 0);
          if (c2 != 0) return c2;
        }

        return a.id.compareTo(b.id);
      });

      return sorted;
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> saveKnockoutMatches(String leagueId, List<KnockoutMatch> matches) async {
    try {
      _requireAuthUid();

      final col = _firestore.collection('leagues').doc(leagueId).collection('knockout');

      final existing = await col.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));

      const chunkSize = 450;

      if (existing.docs.isNotEmpty) {
        for (var i = 0; i < existing.docs.length; i += chunkSize) {
          final batch = _firestore.batch();
          final chunk = existing.docs.sublist(
            i,
            (i + chunkSize > existing.docs.length) ? existing.docs.length : i + chunkSize,
          );
          for (final d in chunk) {
            batch.delete(d.reference);
          }
          await batch.commit().timeout(const Duration(seconds: 30));
        }
      }

      for (var i = 0; i < matches.length; i += chunkSize) {
        final batch = _firestore.batch();
        final chunk = matches.sublist(i, (i + chunkSize > matches.length) ? matches.length : i + chunkSize);
        for (final m in chunk) {
          final id = m.id.trim().isEmpty ? _uuid.v4() : m.id.trim();
          final data = m.copyWith(id: id, leagueId: leagueId).toJson();
          batch.set(col.doc(id), data, SetOptions(merge: true));
        }
        await batch.commit().timeout(const Duration(seconds: 30));
      }
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }
}
