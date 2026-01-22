import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/persistence/prefs_service.dart';
import '../models/league_space.dart';

/// Local-only storage of LeagueSpace per league.
/// Later you can add a remote implementation and swap it in.
class LeagueSpacesLocal {
  LeagueSpacesLocal(this._prefs);

  final PreferencesService _prefs;
  static const _prefix = 'league_space_';
  static const _uuid = Uuid();

  String _key(String leagueId) => '$_prefix$leagueId';

  /// Returns the last known LeagueSpace for this league (may be ended or live).
  Future<LeagueSpace?> getSpace(String leagueId) async {
    final raw = _prefs.getString(_key(leagueId));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return LeagueSpace.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// Returns the active (live) space for this league, or null.
  Future<LeagueSpace?> getActiveSpace(String leagueId) async {
    final s = await getSpace(leagueId);
    if (s == null || !s.isLive) return null;
    return s;
  }

  /// Starts a new live space for this league.
  /// If one already exists, it will be overwritten locally.
  Future<LeagueSpace> startSpace({
    required String leagueId,
    required String hostUserId,
    String? title,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final space = LeagueSpace(
      id: _uuid.v4(),
      leagueId: leagueId,
      hostUserId: hostUserId,
      title: title ?? 'League Space',
      isLive: true,
      createdAtMs: now,
      endedAtMs: null,
    );

    await _prefs.setString(_key(leagueId), jsonEncode(space.toJson()));
    return space;
  }

  /// Marks the space as ended, if any.
  Future<LeagueSpace?> endSpace(String leagueId) async {
    final existing = await getSpace(leagueId);
    if (existing == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = existing.copyWith(
      isLive: false,
      endedAtMs: now,
    );
    await _prefs.setString(_key(leagueId), jsonEncode(updated.toJson()));
    return updated;
  }
}
