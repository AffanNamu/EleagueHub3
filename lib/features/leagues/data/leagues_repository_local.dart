import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
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

    final stored = league.copyWith(
      organizerUserId: organizerUserId,
      code: code,
      updatedAtMs: now,
    );

    await _upsertLeagueLocalNoQueue(stored);

    // organizer membership (local)
    final membership = Membership(
      id: _uuid.v4(),
      leagueId: stored.id,
      userId: organizerUserId,
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

      // IMPORTANT:
      // We always add the userId to memberIds so they have access to the league doc
      // (including "viewer-only" mode for private leagues).
      await firestore.collection('leagues').doc(leagueId).set(
        {
          'memberIds': FieldValue.arrayUnion([userId]),
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      );

      // Pull league doc (now that memberIds includes the user, private get rules will pass)
      final fresh = await firestore.collection('leagues').doc(leagueId).get();
      final data = (fresh.data() ?? <String, dynamic>{});
      data['id'] = leagueId;

      final league = League.fromRemoteMap(data);
      await _upsertLeagueLocalNoQueue(league);

      // --- Membership resolution (important for "admin already added you") ---
      //
      // If admin already added the user, a membership record should exist in cloud.
      // We fetch it and store it locally so the player immediately sees "My Matches".
      final remoteMembership = await _fetchRemoteMembershipForUser(
        firestore: firestore,
        leagueId: leagueId,
        userId: userId,
      );

      final localExisting = await getMembership(leagueId: leagueId, userId: userId);

      final existingMembership = remoteMembership ?? localExisting;

      if (existingMembership != null) {
        // Store/refresh locally (no queue) using leagueId+userId uniqueness.
        await _upsertMembershipLocalByLeagueUserNoQueue(existingMembership);
        return league;
      }

      // No existing membership. Decide whether to create one.
      if (mode == LeagueJoinMode.participant) {
        // Enforce "league full" as: teamsCount + orphanMembershipCount >= league.maxTeams
        // If full -> do NOT create membership (user becomes viewer-only).
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
          // Best-effort: if we can't compute counts, keep prior behavior and allow membership.
          allowParticipantMembership = true;
        }

        if (allowParticipantMembership) {
          final membership = Membership(
            id: _uuid.v4(),
            leagueId: leagueId,
            userId: userId,
            teamId: null,
            role: LeagueRole.member,
            updatedAtMs: now,
            version: 1,
          );
          await _upsertMembershipLocalByLeagueUserNoQueue(membership);

          // Queue membership doc to cloud
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

      // Viewer-only: no membership created.
      return league;
    } on FirebaseException catch (e) {
      // Only fallback to offline placeholder on network-type errors.
      final isNetwork = e.code == 'unavailable' || e.code == 'deadline-exceeded';
      if (!isNetwork) {
        throw StateError('Join failed: ${e.message ?? e.code}');
      }

      // Offline fallback
      final generatedLeagueId = _uuid.v4();
      final placeholder = placeholderBuilder(generatedLeagueId).copyWith(
        code: code,
        updatedAtMs: now,
      );

      await _upsertLeagueLocalNoQueue(placeholder);

      // Queue join for later (always), so the user is added to memberIds in the real league when online.
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

      // PARTICIPANT mode: create membership locally and queue it.
      if (mode == LeagueJoinMode.participant) {
        final membership = Membership(
          id: _uuid.v4(),
          leagueId: generatedLeagueId,
          userId: userId,
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

      // Ensure required keys exist for local model parsing.
      final map = <String, dynamic>{...data};

      // Membership model expects `id` field inside map.
      map['id'] = (map['id'] is String && (map['id'] as String).trim().isNotEmpty) ? map['id'] : doc.id;

      // Ensure leagueId/userId exist in the payload.
      map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
      map['userId'] = (map['userId'] as String?) ?? userId;

      // Defaults for safety
      map['role'] = (map['role'] as num?)?.toInt() ?? LeagueRole.member.index;
      map['updatedAtMs'] = (map['updatedAtMs'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
      map['version'] = (map['version'] as num?)?.toInt() ?? 1;

      return Membership.fromRemoteMap(map);
    } catch (_) {
      return null;
    }
  }

  /// Remote participant count approximation (matches your local UI logic):
  /// registered = (teams count) + (orphan members where role==member and teamId is null/empty)
  ///
  /// NOTE: This is best-effort and depends on those subcollections existing in Firestore.
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

  /// Backend-driven team assignment:
  /// - Admin supplies ONLY userId (Firebase uid)
  /// - Team id can be the same as userId for a stable link
  /// This updates/creates membership so "My Matches" can work without asking for team names.
  Future<void> assignTeamToUserInLeague({
    required String leagueId,
    required String userId,
    required String teamId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final all = await _getAllMemberships();
    final idx = all.indexWhere((m) => m.leagueId == leagueId && m.userId == userId);

    late final Membership updated;
    late final String action;

    if (idx >= 0) {
      final existing = all[idx];
      updated = Membership(
        id: existing.id,
        leagueId: existing.leagueId,
        userId: existing.userId,
        teamId: teamId,
        role: existing.role,
        updatedAtMs: now,
        version: existing.version + 1,
      );
      all[idx] = updated;
      action = 'update';
    } else {
      updated = Membership(
        id: _uuid.v4(),
        leagueId: leagueId,
        userId: userId,
        teamId: teamId,
        role: LeagueRole.member,
        updatedAtMs: now,
        version: 1,
      );
      all.add(updated);
      action = 'create';
    }

    await _prefs.setStringList(
      kMembershipsKey,
      all.map((m) => jsonEncode(m.toRemoteMap())).toList(),
    );

    await _queue.enqueue(
      id: _uuid.v4(),
      entityType: 'membership',
      entityId: updated.id,
      action: action,
      lastModified: now,
      payload: updated.toRemoteMap(),
    );
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
    return all.where((m) => m.leagueId == leagueId).toList();
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

  /// Ensures uniqueness by (leagueId + userId).
  /// This prevents duplicate memberships when a user joins multiple times or was already added by admin.
  Future<void> _upsertMembershipLocalByLeagueUserNoQueue(Membership membership) async {
    final all = await _getAllMemberships();
    final idx = all.indexWhere((m) => m.leagueId == membership.leagueId && m.userId == membership.userId);

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
