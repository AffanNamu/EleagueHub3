import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import '../../../core/persistence/prefs_service.dart';
import '../models/fixture_match.dart';
import '../models/league.dart';
import '../models/membership.dart';
import '../models/team.dart';
import '../models/knockout_match.dart';
import '../models/league_sync_model.dart';

/// Repository responsible for local persistence of League + Membership + Team + Matches data.
/// Offline-first, sync-aware.
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

  Future<void> saveLeague(
    League league, {
    SyncSource source = SyncSource.local,
  }) async {
    final List<League> current = await listLeagues();
    final index = current.indexWhere((l) => l.id == league.id);

    final now = DateTime.now().millisecondsSinceEpoch;

    league = _normalizeLeagueJoinArtifacts(
      league.copyWith(
        lastModified: now,
        syncStatus: SyncStatus.pending,
        syncSource: source,
      ),
    );

    if (index != -1) {
      current[index] = league;
    } else {
      current.add(league);
    }

    final String encoded =
        jsonEncode(current.map((l) => l.toJson()).toList());
    await _prefs.setString(_leaguesKey, encoded);
  }

  /// Completely delete a league and all of its local data
  Future<void> deleteLeagueCompletely(String leagueId) async {
    final leagues = await listLeagues();
    leagues.removeWhere((l) => l.id == leagueId);
    await _prefs.setString(
      _leaguesKey,
      jsonEncode(leagues.map((l) => l.toJson()).toList()),
    );

    final memberships = await listMemberships();
    final filteredMemberships =
        memberships.where((m) => m.leagueId != leagueId).toList();
    await _prefs.setString(
      _membershipsKey,
      jsonEncode(filteredMemberships.map((m) => m.toRemoteMap()).toList()),
    );

    await _prefs.setString('$_teamsKey$leagueId', '[]');
    await _prefs.setString('$_matchesKey$leagueId', '[]');
    await _prefs.setString('$_knockoutsKey$leagueId', '[]');
  }

  /// Creates a new league locally
  Future<League> createLeagueLocally({
    required League league,
    required String organizerUserId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final normalized = _normalizeLeagueJoinArtifacts(
      league.copyWith(
        organizerUserId: organizerUserId,
        lastModified: now,
        syncStatus: SyncStatus.pending,
        syncSource: SyncSource.local,
      ),
    );

    await saveLeague(normalized);

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

  /// Join a league locally (offline-first)
  Future<League> joinLeagueLocallyByCode({
    required String joinCode,
    required String userId,
    required League Function(String generatedLeagueId) placeholderBuilder,
  }) async {
    final leagues = await listLeagues();
    final existing = leagues.where(
      (l) => l.code.toUpperCase() == joinCode.toUpperCase(),
    );

    final League league;

    if (existing.isNotEmpty) {
      league = existing.first;
    } else {
      final generatedLeagueId = _randomId();
      final placeholder = placeholderBuilder(generatedLeagueId);

      league = _normalizeLeagueJoinArtifacts(
        placeholder.copyWith(
          code: joinCode.toUpperCase(),
          lastModified: DateTime.now().millisecondsSinceEpoch,
          syncStatus: SyncStatus.pending,
          syncSource: SyncSource.local,
          qrPayloadOverride:
              'eleaguehub://join?code=${joinCode.toUpperCase()}&id=$generatedLeagueId',
        ),
      );

      await saveLeague(league);
    }

    final now = DateTime.now().millisecondsSinceEpoch;

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
  // Memberships
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
        (m) => m.leagueId == leagueId && m.userId == userId,
      );
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

    await _prefs.setString(
      _membershipsKey,
      jsonEncode(current.map((m) => m.toRemoteMap()).toList()),
    );
  }

  // -----------------------
  // Helpers
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
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
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
