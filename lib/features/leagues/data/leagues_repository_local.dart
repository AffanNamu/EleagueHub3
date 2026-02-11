import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/sync_queue_service.dart';
import '../models/fixture_match.dart';
import '../models/knockout_match.dart';
import '../models/league.dart';
import '../models/membership.dart';
import '../models/team.dart';

/// How a user joins a league from the UI.
///
/// IMPORTANT:
/// - `participant`: user is counted as a league participant (creates/keeps Membership).
/// - `viewer`: user can view the league (added to league.memberIds for access),
///   but is NOT counted as a participant (no new Membership is created).
enum LeagueJoinMode { participant, viewer }

class LocalLeaguesRepository {
  final PreferencesService _prefs;
  final SyncQueueService _queue = SyncQueueService.instance;
  final Uuid _uuid = const Uuid();

  LocalLeaguesRepository(this._prefs);

  static const String kLeaguesKey = 'local_leagues';
  static const String kMembershipsKey = 'local_memberships';
  static const String kTeamsKey = 'local_teams';
  static const String kMatchesKey = 'local_matches';
  static const String kKnockoutMatchesKey = 'local_knockout_matches';

  // -----------------------
  // Leagues
  // -----------------------

  Future<List<League>> listLeagues() => getAllLeagues();

  Future<List<League>> getAllLeagues() async {
    final raw = _prefs.getStringList(kLeaguesKey) ?? <String>[];

    // Defensive: do not crash the whole app if one stored entry is malformed.
    final out = <League>[];
    for (final s in raw) {
      try {
        out.add(League.fromJsonString(s));
      } catch (_) {
        // Skip bad record (non-fatal)
      }
    }
    return out;
  }

  Future<League?> getLeagueById(String id) async {
    final all = await getAllLeagues();
    for (final l in all) {
      if (l.id == id) return l;
    }
    return null;
  }

  Future<void> saveLeague(League league) async {
    final all = await getAllLeagues();
    final existsIndex = all.indexWhere((l) => l.id == league.id);

    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = league.copyWith(updatedAtMs: now);

    if (existsIndex >= 0) {
      all[existsIndex] = updated;
    } else {
      all.add(updated);
    }

    await _prefs.setStringList(
      kLeaguesKey,
      all.map((l) => l.toJsonString()).toList(),
    );

    await _queue.enqueue(
      id: _uuid.v4(),
      entityType: 'league',
      entityId: updated.id,
      action: existsIndex >= 0 ? 'update' : 'create',
      lastModified: now,
      payload: updated.toJson(),
    );
  }

  Future<void> deleteLeagueCompletely(String leagueId) async {
    final leagues = await getAllLeagues();
    leagues.removeWhere((l) => l.id == leagueId);
    await _prefs.setStringList(
      kLeaguesKey,
      leagues.map((l) => l.toJsonString()).toList(),
    );

    final teams = await _getAllTeams();
    teams.removeWhere((t) => t.leagueId == leagueId);
    await _prefs.setStringList(
      kTeamsKey,
      teams.map((t) => jsonEncode(t.toRemoteMap())).toList(),
    );

    final memberships = await _getAllMemberships();
    memberships.removeWhere((m) => m.leagueId == leagueId);
    await _prefs.setStringList(
      kMembershipsKey,
      memberships.map((m) => jsonEncode(m.toRemoteMap())).toList(),
    );

    final matches = await _getAllMatches();
    matches.removeWhere((m) => m.leagueId == leagueId);
    await _prefs.setStringList(
      kMatchesKey,
      matches.map((m) => jsonEncode(m.toJson())).toList(),
    );

    final ko = await _getAllKnockoutMatches();
    ko.removeWhere((m) => m.leagueId == leagueId);
    await _prefs.setStringList(
      kKnockoutMatchesKey,
      ko.map((m) => jsonEncode(m.toJson())).toList(),
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    await _queue.enqueue(
      id: _uuid.v4(),
      entityType: 'league',
      entityId: leagueId,
      action: 'delete',
      lastModified: now,
      payload: null,
    );
  }

  // ------------------------------------------------------
  // CREATE (local)
  // ------------------------------------------------------

  Future<League> createLeagueLocally({
    required League league,
    required String organizerUserId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final code = (league.code.trim().isNotEmpty) ? league.code.trim().toUpperCase() : _generateJoinCode();

    // Rules authority: FirebaseAuth uid (anonymous or real).
    final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();

    final inferredOrganizerUid = authUid.isNotEmpty ? authUid : league.organizerUid.trim();

    final stored = league.copyWith(
      organizerUid: inferredOrganizerUid,
      organizerUserId: organizerUserId,
      code: code,
      updatedAtMs: now,
    );

    await _upsertLeagueLocalNoQueue(stored);

    // organizer membership (local)
    final membership = Membership(
      id: _uuid.v4(),
      leagueId: stored.id,
      userId: authUid.isNotEmpty ? authUid : organizerUserId,
      teamId: null,
      role: LeagueRole.organizer,
      updatedAtMs: now,
      version: 1,
    );
    await _upsertMembershipLocalByLeagueUserNoQueue(membership);

    // queue league create
    await _queue.enqueue(
      id: _uuid.v4(),
      entityType: 'league',
      entityId: stored.id,
      action: 'create',
      lastModified: now,
      payload: stored.toJson(),
    );

    // queue membership create
    await _queue.enqueue(
      id: _uuid.v4(),
      entityType: 'membership',
      entityId: membership.id,
      action: 'create',
      lastModified: now,
      payload: membership.toRemoteMap(),
    );

    return stored;
  }

  // ------------------------------------------------------
  // JOIN by code (strict online, offline fallback only on network error)
  // ------------------------------------------------------

  Future<League> joinLeagueLocallyByCode({
    required String joinCode,
    required String userId,
    required League Function(String generatedLeagueId) placeholderBuilder,
    LeagueJoinMode mode = LeagueJoinMode.participant,
  }) async {
    final code = joinCode.trim().toUpperCase();
    final now = DateTime.now().millisecondsSinceEpoch;

    final firestore = FirebaseFirestore.instance;

    try {
      // Always try ONLINE first (don't trust connectivity flag)
      final query = await firestore.collection('leagues').where('code', isEqualTo: code).limit(1).get();

      if (query.docs.isEmpty) {
        // Online reachable but league not found: DO NOT create placeholder
        throw StateError(
          'League not found online. Ask admin to sync and share the correct Join ID.',
        );
      }

      final doc = query.docs.first;
      final leagueId = doc.id;

      // RULES AUTHORITY:
      // memberIds must append exactly +1 element (request.auth.uid only).
      final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      if (authUid.isEmpty) {
        throw StateError('Sign in required to join this league.');
      }

      await firestore.collection('leagues').doc(leagueId).set(
        {
          'memberIds': FieldValue.arrayUnion([authUid]),
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      );

      final fresh = await firestore.collection('leagues').doc(leagueId).get();
      final data = (fresh.data() ?? <String, dynamic>{});
      data['id'] = leagueId;

      final league = League.fromRemoteMap(data);
      await _upsertLeagueLocalNoQueue(league);

      // Memberships should use Firebase UID in modern flows
      final effectiveMembershipUserId = authUid;

      final remoteMembership = await _fetchRemoteMembershipForUser(
        firestore: firestore,
        leagueId: leagueId,
        userId: effectiveMembershipUserId,
      );

      final localExisting = await getMembership(leagueId: leagueId, userId: effectiveMembershipUserId);

      final existingMembership = remoteMembership ?? localExisting;

      if (existingMembership != null) {
        await _upsertMembershipLocalByLeagueUserNoQueue(existingMembership);
        return league;
      }

      if (mode == LeagueJoinMode.participant) {
        bool allowParticipantMembership = true;
        try {
          final registered = await _fetchRemoteRegisteredCount(
            firestore: firestore,
            leagueId: leagueId,
          );
          if (registered >= league.maxTeams) {
            allowParticipantMembership = false;
          }
        } catch (_) {
          allowParticipantMembership = true;
        }

        if (allowParticipantMembership) {
          final membership = Membership(
            id: _uuid.v4(),
            leagueId: leagueId,
            userId: effectiveMembershipUserId,
            teamId: null,
            role: LeagueRole.member,
            updatedAtMs: now,
            version: 1,
          );
          await _upsertMembershipLocalByLeagueUserNoQueue(membership);

          await _queue.enqueue(
            id: _uuid.v4(),
            entityType: 'membership',
            entityId: membership.id,
            action: 'create',
            lastModified: now,
            payload: membership.toRemoteMap(),
          );
        }
      }

      return league;
    } on FirebaseException catch (e) {
      final isNetwork = e.code == 'unavailable' || e.code == 'deadline-exceeded';
      if (!isNetwork) {
        throw StateError('Join failed: ${e.message ?? e.code}');
      }

      final generatedLeagueId = _uuid.v4();
      final placeholder = placeholderBuilder(generatedLeagueId).copyWith(
        code: code,
        updatedAtMs: now,
      );

      await _upsertLeagueLocalNoQueue(placeholder);

      final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      await _queue.enqueue(
        id: _uuid.v4(),
        entityType: 'league_join',
        entityId: generatedLeagueId,
        action: 'join',
        lastModified: now,
        payload: {
          'code': code,
          // legacy/local id (kept for old UI / analytics)
          'userId': userId,
          // rules-authoritative id (preferred)
          if (authUid.isNotEmpty) 'authUid': authUid,
        },
      );

      if (mode == LeagueJoinMode.participant) {
        final effectiveMembershipUserId = authUid.isNotEmpty ? authUid : userId;

        final membership = Membership(
          id: _uuid.v4(),
          leagueId: generatedLeagueId,
          userId: effectiveMembershipUserId,
          teamId: null,
          role: LeagueRole.member,
          updatedAtMs: now,
          version: 1,
        );
        await _upsertMembershipLocalByLeagueUserNoQueue(membership);

        await _queue.enqueue(
          id: _uuid.v4(),
          entityType: 'membership',
          entityId: membership.id,
          action: 'create',
          lastModified: now,
          payload: membership.toRemoteMap(),
        );
      }

      return placeholder;
    }
  }

  Future<Membership?> _fetchRemoteMembershipForUser({
    required FirebaseFirestore firestore,
    required String leagueId,
    required String userId,
  }) async {
    try {
      final snap = await firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('memberships')
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) return null;

      final doc = snap.docs.first;
      final data = doc.data();

      final map = <String, dynamic>{...data};

      map['id'] = (map['id'] is String && (map['id'] as String).trim().isNotEmpty) ? map['id'] : doc.id;

      map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
      map['userId'] = (map['userId'] as String?) ?? userId;

      map['role'] = (map['role'] as num?)?.toInt() ?? LeagueRole.member.index;
      map['updatedAtMs'] = (map['updatedAtMs'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
      map['version'] = (map['version'] as num?)?.toInt() ?? 1;

      return Membership.fromRemoteMap(map);
    } catch (_) {
      return null;
    }
  }

  Future<int> _fetchRemoteRegisteredCount({
    required FirebaseFirestore firestore,
    required String leagueId,
  }) async {
    final teamsSnap = await firestore.collection('leagues').doc(leagueId).collection('teams').get();
    final membershipsSnap = await firestore.collection('leagues').doc(leagueId).collection('memberships').get();

    final teamsCount = teamsSnap.size;

    int orphanMembersCount = 0;
    for (final d in membershipsSnap.docs) {
      final data = d.data();
      final role = (data['role'] as num?)?.toInt();
      final teamId = data['teamId'] as String?;
      final isMember = role == LeagueRole.member.index;
      final isOrphan = teamId == null || teamId.trim().isEmpty;
      if (isMember && isOrphan) orphanMembersCount++;
    }

    return teamsCount + orphanMembersCount;
  }

  // ------------------------------------------------------
  // Memberships
  // ------------------------------------------------------

  Future<List<Membership>> listMemberships() async => _getAllMemberships();

  Future<Membership?> getMembership({
    required String leagueId,
    required String userId,
  }) async {
    final all = await _getAllMemberships();
    for (final m in all) {
      if (m.leagueId == leagueId && m.userId == userId) return m;
    }
    return null;
  }

  // ------------------------------------------------------
  // Teams
  // ------------------------------------------------------

  Future<List<Team>> getTeams(String leagueId) async {
    final all = await _getAllTeams();
    return all.where((t) => t.leagueId == leagueId).toList();
  }

  Future<void> saveTeams(String leagueId, List<Team> allTeams) async {
    final teams = await _getAllTeams();
    teams.removeWhere((t) => t.leagueId == leagueId);
    teams.addAll(allTeams);

    await _prefs.setStringList(
      kTeamsKey,
      teams.map((t) => jsonEncode(t.toRemoteMap())).toList(),
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    await _queue.enqueue(
      id: _uuid.v4(),
      entityType: 'teams_replace',
      entityId: leagueId,
      action: 'replace',
      lastModified: now,
      payload: {
        'leagueId': leagueId,
        'teams': allTeams.map((t) => t.toRemoteMap()).toList(),
      },
    );
  }

  // ------------------------------------------------------
  // Matches / Fixtures
  // ------------------------------------------------------

  Future<List<FixtureMatch>> getMatches(String leagueId) async {
    final all = await _getAllMatches();
    return all.where((m) => m.leagueId == leagueId).toList();
  }

  Future<void> saveMatches(String leagueId, List<FixtureMatch> matches) async {
    final all = await _getAllMatches();

    for (final m in matches) {
      final idx = all.indexWhere((x) => x.id == m.id);
      if (idx >= 0) {
        all[idx] = m;
      } else {
        all.add(m);
      }
    }

    await _prefs.setStringList(
      kMatchesKey,
      all.map((m) => jsonEncode(m.toJson())).toList(),
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    await _queue.enqueue(
      id: _uuid.v4(),
      entityType: 'matches_upsert',
      entityId: leagueId,
      action: 'upsert',
      lastModified: now,
      payload: {
        'leagueId': leagueId,
        'matches': matches.map((m) => m.toJson()).toList(),
      },
    );
  }

  Future<void> replaceMatches(String leagueId, List<FixtureMatch> matches) async {
    final all = await _getAllMatches();
    all.removeWhere((m) => m.leagueId == leagueId);
    all.addAll(matches);

    await _prefs.setStringList(
      kMatchesKey,
      all.map((m) => jsonEncode(m.toJson())).toList(),
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    await _queue.enqueue(
      id: _uuid.v4(),
      entityType: 'matches_replace',
      entityId: leagueId,
      action: 'replace',
      lastModified: now,
      payload: {
        'leagueId': leagueId,
        'matches': matches.map((m) => m.toJson()).toList(),
      },
    );
  }

  // ------------------------------------------------------
  // Knockout matches
  // ------------------------------------------------------

  Future<List<KnockoutMatch>> getKnockoutMatches(String leagueId) async {
    final all = await _getAllKnockoutMatches();
    final list = all.where((m) => m.leagueId == leagueId).toList();

    const roundOrder = <String>[
      'Play-off',
      'Round of 16',
      'Quarter Finals',
      'Semi Finals',
      'Final',
      '3rd Place',
    ];

    list.sort((a, b) {
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

    return list;
  }

  Future<void> saveKnockoutMatches(String leagueId, List<KnockoutMatch> matches) async {
    final all = await _getAllKnockoutMatches();
    all.removeWhere((m) => m.leagueId == leagueId);
    all.addAll(matches);

    await _prefs.setStringList(
      kKnockoutMatchesKey,
      all.map((m) => jsonEncode(m.toJson())).toList(),
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    await _queue.enqueue(
      id: _uuid.v4(),
      entityType: 'knockout_replace',
      entityId: leagueId,
      action: 'replace',
      lastModified: now,
      payload: {
        'leagueId': leagueId,
        'matches': matches.map((m) => m.toJson()).toList(),
      },
    );
  }

  // ------------------------------------------------------
  // Internal local storage helpers
  // ------------------------------------------------------

  Future<void> _upsertLeagueLocalNoQueue(League league) async {
    final all = await getAllLeagues();
    final idx = all.indexWhere((l) => l.id == league.id);
    if (idx >= 0) {
      all[idx] = league;
    } else {
      all.add(league);
    }

    await _prefs.setStringList(
      kLeaguesKey,
      all.map((l) => l.toJsonString()).toList(),
    );
  }

  Future<List<Membership>> _getAllMemberships() async {
    final raw = _prefs.getStringList(kMembershipsKey) ?? <String>[];
    return raw.map((e) {
      final map = (jsonDecode(e) as Map).cast<String, dynamic>();
      return Membership.fromRemoteMap(map);
    }).toList();
  }

  Future<void> _upsertMembershipLocalByLeagueUserNoQueue(Membership membership) async {
    final all = await _getAllMemberships();

    all.removeWhere((m) => m.leagueId == membership.leagueId && m.userId == membership.userId);
    all.add(membership);

    await _prefs.setStringList(
      kMembershipsKey,
      all.map((m) => jsonEncode(m.toRemoteMap())).toList(),
    );
  }

  Future<List<Team>> _getAllTeams() async {
    final raw = _prefs.getStringList(kTeamsKey) ?? <String>[];
    return raw.map((e) {
      final map = (jsonDecode(e) as Map).cast<String, dynamic>();
      return Team.fromRemoteMap(map);
    }).toList();
  }

  Future<List<FixtureMatch>> _getAllMatches() async {
    final raw = _prefs.getStringList(kMatchesKey) ?? <String>[];
    return raw.map((e) {
      final map = (jsonDecode(e) as Map).cast<String, dynamic>();
      return FixtureMatch.fromJson(map);
    }).toList();
  }

  Future<List<KnockoutMatch>> _getAllKnockoutMatches() async {
    final raw = _prefs.getStringList(kKnockoutMatchesKey) ?? <String>[];
    return raw.map((e) {
      final map = (jsonDecode(e) as Map).cast<String, dynamic>();
      return KnockoutMatch.fromJson(map);
    }).toList();
  }

  String _generateJoinCode({int length = 6}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}
