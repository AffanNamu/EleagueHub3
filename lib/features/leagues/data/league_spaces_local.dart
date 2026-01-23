import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/sync_queue_service.dart';
import '../models/league_space.dart';

/// Local cache of LeagueSpace per league.
/// Also enqueues changes for Firestore sync.
/// Firestore target: /leagues/{leagueId}/space/current (single doc)
class LeagueSpacesFirebase {
  LeagueSpacesFirebase(this._prefs);

  final PreferencesService _prefs;
  final SyncQueueService _queue = SyncQueueService.instance;

  static const _prefix = 'league_space_';
  static const _uuid = Uuid();

  String _key(String leagueId) => '$_prefix$leagueId';

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

  Future<LeagueSpace?> getActiveSpace(String leagueId) async {
    final s = await getSpace(leagueId);
    if (s == null || !s.isLive) return null;
    return s;
  }

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

    // Enqueue for cloud
    await _queue.enqueue(
      id: _uuid.v4(),
      entityType: 'space_current',
      entityId: leagueId, // entityId is leagueId for current-space doc
      action: 'upsert',
      lastModified: now,
      payload: space.toJson(),
    );

    return space;
  }

  Future<LeagueSpace?> endSpace(String leagueId) async {
    final existing = await getSpace(leagueId);
    if (existing == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = existing.copyWith(isLive: false, endedAtMs: now);

    await _prefs.setString(_key(leagueId), jsonEncode(updated.toJson()));

    // Enqueue for cloud
    await _queue.enqueue(
      id: _uuid.v4(),
      entityType: 'space_current',
      entityId: leagueId,
      action: 'upsert',
      lastModified: now,
      payload: updated.toJson(),
    );

    return updated;
  }
}
