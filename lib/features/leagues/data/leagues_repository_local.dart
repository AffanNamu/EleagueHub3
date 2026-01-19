import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import '../../../core/persistence/prefs_service.dart';
import '../models/fixture_match.dart';
import '../models/league.dart';
import '../models/membership.dart';
import '../models/team.dart';
import '../models/knockout_match.dart';

/// Repository responsible for local persistence of League + Membership + Team + Matches data.
/// Uses SharedPreferences via the PreferencesService.
///
/// Added:
/// - Offline-safe Join ID (invite code) generation
/// - Offline-safe QR payload generation
/// - Local membership persistence (organizer/member) so participant cannot edit
class LocalLeaguesRepository {
  final PreferencesService _prefs;

  LocalLeaguesRepository(this._prefs);

  // Storage keys
  static const String _leaguesKey = 'stored_leagues';
  static const String _membershipsKey = 'stored_memberships';
  static const String _teamsKey = 'stored_teams_';
  static const String _matchesKey = 'stored_matches_';
  static const String _knockoutsKey = 'stored_knockouts_';

  // -----------------------
  // Leagues
  // -----------------------

  Future<List<League>> listLeagues() async {
    final String? data = _prefs.getString(_leaguesKey);
    if (data == null) return [];
    try {
      final List decoded = jsonDecode(data);
      final leagues = decoded
          .map((item) => League.fromRemoteMap(item as Map<String, dynamic>))
          .toList()
          .cast<League>();

      return leagues.map(_normalizeLeagueJoinArtifacts).toList();
    } catch (e) {
      debugPrint('Error decoding leagues: $e');
      return [];
    }
  }

  Future<League?> getLeagueById(String leagueId) async {
    final leagues = await listLeagues();
    try {
      return leagues.firstWhere((l) => l.id == leagueId);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLeague(League league) async {
    final List<League> current = await listLeagues();
    final index = current.indexWhere((l) => l.id == league.id);

    league = _normalizeLeagueJoinArtifacts(league);

    if (index != -1) {
      current[index] = league;
    } else {
      current.add(league);
    }

    final String encoded = jsonEncode(current.map((l) => l.toJson()).toList());
    await _prefs.setString(_leaguesKey, encoded);
  }

  /// Completely delete a league and all of its local data:
  /// - League entry
  /// - Memberships for that league
  /// - Teams, league matches, knockout matches
  Future<void> deleteLeagueCompletely(String leagueId) async {
    // 1) Remove league from list
    final leagues = await listLeagues();
    leagues.removeWhere((l) => l.id == leagueId);
    final leaguesEncoded =
        jsonEncode(leagues.map((l) => l.toJson()).toList());
    await _prefs.setString(_leaguesKey, leaguesEncoded);

    // 2) Remove memberships for this league
    final memberships = await listMemberships();
    final filteredMemberships =
        memberships.where((m) => m.leagueId != leagueId).toList();
    final membershipsEncoded = jsonEncode(
      filteredMemberships.map((m) => m.toRemoteMap()).toList(),
    );
    await _prefs.setString(_membershipsKey, membershipsEncoded);

    // 3) Clear league-specific data (teams, matches, knockouts)
    await _prefs.setString('$_teamsKey$leagueId', '[]');
    await _prefs.setString('$_matchesKey$leagueId', '[]');
    await _prefs.setString('$_knockoutsKey$leagueId', '[]');
  }

  /// Creates a new league locally and also creates organizer membership for [organizerUserId].
  Future<League> createLeagueLocally({
    required League league,
    required String organizerUserId,
  }) async {
    final normalized = _normalizeLeagueJoinArtifacts(
      league.copyWith(organizerUserId: organizerUserId),
    );

    await saveLeague(normalized);

    final now = DateTime.now().millisecondsSinceEpoch;
    await saveMembership(
      Membership(
        id: _randomId(),
        leagueId: normalized.id,
        userId: organizerUserId,
        teamId: null,
        role: LeagueRole.organizer,
        updatedAtMs: now,
        version: 1,
      ),
    );

    return normalized;
  }

  /// Join a league locally (offline-first).
  ///
  /// If the league doesn't exist locally, we create a placeholder league record.
  /// We also create a MEMBER membership for [userId].
  Future<League> joinLeagueLocallyByCode({
    required String joinCode,
    required String userId,
    required League Function(String generatedLeagueId) placeholderBuilder,
  }) async {
    final leagues = await listLeagues();
    final existing =
        leagues.where((l) => l.code.toUpperCase() == joinCode.toUpperCase()).toList();
    final League league;

    if (existing.isNotEmpty) {
      league = existing.first;
    } else {
      final generatedLeagueId = _randomId();
      final placeholder = placeholderBuilder(generatedLeagueId);
      league = _normalizeLeagueJoinArtifacts(
        placeholder.copyWith(
          code: joinCode.toUpperCase(),
          qrPayloadOverride:
              'eleaguehub://join?code=${joinCode.toUpperCase()}&id=$generatedLeagueId',
        ),
      );
      await saveLeague(league);
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    // Ensure membership exists
    final already =
        await getMembership(leagueId: league.id, userId: userId);
    if (already == null) {
      await saveMembership(
        Membership(
          id: _randomId(),
          leagueId: league.id,
          userId: userId,
          teamId: null,
          role: LeagueRole.member,
          updatedAtMs: now,
          version: 1,
        ),
      );
    }

    return league;
  }

  // -----------------------
  // Memberships (roles)
  // -----------------------

  Future<List<Membership>> listMemberships() async {
    final String? data = _prefs.getString(_membershipsKey);
    if (data == null) return [];
    try {
      final List decoded = jsonDecode(data);
      return decoded
          .map((m) => Membership.fromRemoteMap((m as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      debugPrint('Error decoding memberships: $e');
      return [];
    }
  }

  Future<Membership?> getMembership({
    required String leagueId,
    required String userId,
  }) async {
    final all = await listMemberships();
    try {
      return all.firstWhere(
          (m) => m.leagueId == leagueId && m.userId == userId);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveMembership(Membership membership) async {
    final current = await listMemberships();
    final idx = current.indexWhere((m) => m.id == membership.id);

    if (idx != -1) {
      current[idx] = membership;
    } else {
      current.add(membership);
    }

    final encoded =
        jsonEncode(current.map((m) => m.toRemoteMap()).toList());
    await _prefs.setString(_membershipsKey, encoded);
  }

  // -----------------------
  // Teams
  // -----------------------

  Future<void> saveTeams(String leagueId, List<Team> teams) async {
    final String encoded =
        jsonEncode(teams.map((t) => t.toRemoteMap()).toList());
    await _prefs.setString('$_teamsKey$leagueId', encoded);
  }

  Future<List<Team>> getTeams(String leagueId) async {
    final String? data = _prefs.getString('$_teamsKey$leagueId');
    if (data == null) return [];
    try {
      final List decoded = jsonDecode(data);
      return decoded
          .map((t) => Team.fromRemoteMap(t as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error decoding teams for $leagueId: $e');
      return [];
    }
  }

  // -----------------------
  // Matches (League Phase)
  // -----------------------

  Future<List<FixtureMatch>> getMatches(String leagueId) async {
    final String? data = _prefs.getString('$_matchesKey$leagueId');
    if (data == null) return [];
    try {
      final List decoded = jsonDecode(data);
      return decoded
          .map((m) => FixtureMatch.fromJson(m as Map<String, dynamic>))
          .toList()
          .cast<FixtureMatch>();
    } catch (e) {
      debugPrint('Error decoding matches for $leagueId: $e');
      return [];
    }
  }

  /// Merge new matches into existing matches (used in some flows).
  Future<void> saveMatches(String leagueId, List<FixtureMatch> matches) async {
    final List<FixtureMatch> existing = await getMatches(leagueId);
    final Map<String, FixtureMatch> matchMap = {
      for (var m in existing) m.id: m
    };

    for (var m in matches) {
      matchMap[m.id] = m;
    }

    final String encoded =
        jsonEncode(matchMap.values.map((m) => m.toJson()).toList());
    await _prefs.setString('$_matchesKey$leagueId', encoded);
  }

  /// Replace all league-phase matches for [leagueId] with [matches].
  /// Used when regenerating fixtures after teams are added.
  Future<void> replaceMatches(String leagueId, List<FixtureMatch> matches) async {
    final String encoded =
        jsonEncode(matches.map((m) => m.toJson()).toList());
    await _prefs.setString('$_matchesKey$leagueId', encoded);
  }

  // -----------------------
  // Knockout Matches (Bracket)
  // -----------------------

  Future<List<KnockoutMatch>> getKnockoutMatches(String leagueId) async {
    final String? data = _prefs.getString('$_knockoutsKey$leagueId');
    if (data == null) return [];
    try {
      final List decoded = jsonDecode(data);
      return decoded
          .map((m) => KnockoutMatch.fromJson(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error decoding knockouts for $leagueId: $e');
      return [];
    }
  }

  Future<void> saveKnockoutMatches(
    String leagueId,
    List<KnockoutMatch> matches,
  ) async {
    final existing = await getKnockoutMatches(leagueId);
    final map = <String, KnockoutMatch>{
      for (final m in existing) m.id: m,
    };

    for (final m in matches) {
      map[m.id] = m;
    }

    final encoded =
        jsonEncode(map.values.map((m) => m.toJson()).toList());
    await _prefs.setString('$_knockoutsKey$leagueId', encoded);
  }

  // -----------------------
  // Join artifacts helpers
  // -----------------------

  League _normalizeLeagueJoinArtifacts(League league) {
    var code = league.code.trim();
    if (code.isEmpty) {
      code = _generateJoinCode(seed: league.id);
    }

    var qrPayload = league.qrPayloadOverride.trim();
    if (qrPayload.isEmpty) {
      qrPayload = 'eleaguehub://join?code=$code&id=${league.id}';
    }

    if (code == league.code && qrPayload == league.qrPayloadOverride) {
      return league;
    }

    return league.copyWith(
      code: code,
      qrPayloadOverride: qrPayload,
    );
  }

  String _generateJoinCode({required String seed, int length = 8}) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no O/0 I/1
    final seedHash = seed.hashCode.abs();
    final rng =
        Random(seedHash ^ DateTime.now().millisecondsSinceEpoch);
    return List.generate(
      length,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
  }

  String _randomId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final r = Random().nextInt(1 << 32);
    return '$ms-$r';
  }
}
