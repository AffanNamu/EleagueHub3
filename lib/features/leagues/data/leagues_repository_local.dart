import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_queue_service.dart';
import '../models/fixture_match.dart';
import '../models/league.dart';
import '../models/membership.dart';
import '../models/team.dart';

class LocalLeaguesRepository {
  final PreferencesService _prefs;
  final SyncQueueService _queue = SyncQueueService.instance;
  final Uuid _uuid = const Uuid();

  LocalLeaguesRepository(this._prefs);

  static const String kLeaguesKey = 'local_leagues';
  static const String kMembershipsKey = 'local_memberships';
  static const String kTeamsKey = 'local_teams';

  /// All matches for all leagues (simple, ok for now)
  static const String kMatchesKey = 'local_matches';

  // -----------------------
  // Leagues
  // -----------------------

  Future<List<League>> listLeagues() => getAllLeagues();

  Future<List<League>> getAllLeagues() async {
    final raw = _prefs.getStringList(kLeaguesKey) ?? <String>[];
    return raw.map(League.fromJsonString).toList();
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
    // remove league
    final leagues = await getAllLeagues();
    leagues.removeWhere((l) => l.id == leagueId);
    await _prefs.setStringList(
      kLeaguesKey,
      leagues.map((l) => l.toJsonString()).toList(),
    );

    // remove teams for league
    final teams = await _getAllTeams();
    teams.removeWhere((t) => t.leagueId == leagueId);
    await _prefs.setStringList(
      kTeamsKey,
      teams.map((t) => jsonEncode(t.toRemoteMap())).toList(),
    );

    // remove memberships for league
    final memberships = await _getAllMemberships();
    memberships.removeWhere((m) => m.leagueId == leagueId);
    await _prefs.setStringList(
      kMembershipsKey,
      memberships.map((m) => jsonEncode(m.toRemoteMap())).toList(),
    );

    // remove matches for league
    final matches = await _getAllMatches();
    matches.removeWhere((m) => m.leagueId == leagueId);
    await _prefs.setStringList(
      kMatchesKey,
      matches.map((m) => jsonEncode(m.toJson())).toList(),
    );

    // queue delete to cloud
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

    final code = (league.code.trim().isNotEmpty)
        ? league.code.trim().toUpperCase()
        : _generateJoinCode();

    final stored = league.copyWith(
      organizerUserId: organizerUserId,
      code: code,
      updatedAtMs: now,
    );

    await _upsertLeagueLocalNoQueue(stored);

    // organizer membership
    final membership = Membership(
      id: _uuid.v4(),
      leagueId: stored.id,
      userId: organizerUserId,
      teamId: null,
      role: LeagueRole.organizer,
      updatedAtMs: now,
      version: 1,
    );
    await _upsertMembershipLocalNoQueue(membership);

    // queue league create
    await _queue.enqueue(
      id: _uuid.v4(),
      entityType: 'league',
      entityId: stored.id,
      action: 'create',
      lastModified: now,
      payload: stored.toJson(),
    );

    // optional: membership queue
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
  // JOIN by code (online-first, offline fallback)
  // ------------------------------------------------------

  Future<League> joinLeagueLocallyByCode({
    required String joinCode,
    required String userId,
    required League Function(String generatedLeagueId) placeholderBuilder,
  }) async {
    final code = joinCode.trim().toUpperCase();
    final now = DateTime.now().millisecondsSinceEpoch;

    final online = ConnectivityService.instance.isConnected.value;
    if (online) {
      final firestore = FirebaseFirestore.instance;

      final query = await firestore
          .collection('leagues')
          .where('code', isEqualTo: code)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        throw StateError('League not found for Join ID: $code');
      }

      final doc = query.docs.first;
      final leagueId = doc.id;

      await firestore.collection('leagues').doc(leagueId).set(
        {
          'memberIds': FieldValue.arrayUnion([userId]),
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      );

      final fresh = await firestore.collection('leagues').doc(leagueId).get();
      final data = (fresh.data() ?? <String, dynamic>{});
      data['id'] = leagueId;

      final league = League.fromRemoteMap(data);
      await _upsertLeagueLocalNoQueue(league);

      // local membership
      final membership = Membership(
        id: _uuid.v4(),
        leagueId: leagueId,
        userId: userId,
        teamId: null,
        role: LeagueRole.member,
        updatedAtMs: now,
        version: 1,
      );
      await _upsertMembershipLocalNoQueue(membership);

      // optional membership queue
      await _queue.enqueue(
        id: _uuid.v4(),
        entityType: 'membership',
        entityId: membership.id,
        action: 'create',
        lastModified: now,
        payload: membership.toRemoteMap(),
      );

      return league;
    }

    // Offline fallback
    final generatedLeagueId = _uuid.v4();
    final placeholder = placeholderBuilder(generatedLeagueId).copyWith(
      code: code,
      updatedAtMs: now,
    );

    await _upsertLeagueLocalNoQueue(placeholder);

    // local membership
    final membership = Membership(
      id: _uuid.v4(),
      leagueId: generatedLeagueId,
      userId: userId,
      teamId: null,
      role: LeagueRole.member,
      updatedAtMs: now,
      version: 1,
    );
    await _upsertMembershipLocalNoQueue(membership);

    // queue join for later
    await _queue.enqueue(
      id: _uuid.v4(),
      entityType: 'league_join',
      entityId: generatedLeagueId,
      action: 'join',
      lastModified: now,
      payload: {
        'code': code,
        'userId': userId,
      },
    );

    // optional membership queue
    await _queue.enqueue(
      id: _uuid.v4(),
      entityType: 'membership',
      entityId: membership.id,
      action: 'create',
      lastModified: now,
      payload: membership.toRemoteMap(),
    );

    return placeholder;
  }

  // ------------------------------------------------------
  // MEMBERSHIPS
  // ------------------------------------------------------

  Future<List<Membership>> listMemberships() async => _getAllMemberships();

  Future<List<Membership>> listMembershipsForLeague(String leagueId) async {
    final all = await _getAllMemberships();
    return all.where((m) => m.leagueId == leagueId).toList();
  }

  // ------------------------------------------------------
  // TEAMS
  // ------------------------------------------------------

  Future<List<Team>> getTeams(String leagueId) async {
    final all = await _getAllTeams();
    return all.where((t) => t.leagueId == leagueId).toList();
  }

  /// AddTeamsScreen calls this to overwrite all teams of a league at once.
  Future<void> saveTeams(String leagueId, List<Team> allTeams) async {
    // Remove old teams for league, then add provided
    final teams = await _getAllTeams();
    teams.removeWhere((t) => t.leagueId == leagueId);
    teams.addAll(allTeams);

    await _prefs.setStringList(
      kTeamsKey,
      teams.map((t) => jsonEncode(t.toRemoteMap())).toList(),
    );

    // Queue a simple "teams_replace" action (optional).
    // If you don't want to sync teams yet, you can remove this.
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
  // MATCHES / FIXTURES
  // ------------------------------------------------------

  Future<List<FixtureMatch>> getMatches(String leagueId) async {
    final all = await _getAllMatches();
    return all.where((m) => m.leagueId == leagueId).toList();
  }

  Future<void> replaceMatches(String leagueId, List<FixtureMatch> matches) async {
    final all = await _getAllMatches();
    all.removeWhere((m) => m.leagueId == leagueId);
    all.addAll(matches);

    await _prefs.setStringList(
      kMatchesKey,
      all.map((m) => jsonEncode(m.toJson())).toList(),
    );

    // Queue a simple "matches_replace" action (optional).
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

  Future<void> _upsertMembershipLocalNoQueue(Membership membership) async {
    final all = await _getAllMemberships();
    final idx = all.indexWhere((m) => m.id == membership.id);
    if (idx >= 0) {
      all[idx] = membership;
    } else {
      all.add(membership);
    }

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

  String _generateJoinCode({int length = 6}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}
