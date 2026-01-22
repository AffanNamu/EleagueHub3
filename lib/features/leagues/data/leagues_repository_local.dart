import 'package:uuid/uuid.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/sync_queue_service.dart';
import '../models/league.dart';

class LocalLeaguesRepository {
  final PreferencesService _prefs;
  final SyncQueueService _queue = SyncQueueService.instance;
  final Uuid _uuid = const Uuid();

  LocalLeaguesRepository(this._prefs);

  static const String kLeaguesKey = 'local_leagues';

  // -----------------------
  // Leagues (used by UI)
  // -----------------------

  Future<List<League>> listLeagues() => getAllLeagues();

  Future<List<League>> getAllLeagues() async {
    final raw = _prefs.getStringList(kLeaguesKey) ?? [];
    return raw.map((e) => League.fromJsonString(e)).toList();
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
    final all = await getAllLeagues();
    all.removeWhere((l) => l.id == leagueId);

    await _prefs.setStringList(
      kLeaguesKey,
      all.map((l) => l.toJsonString()).toList(),
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
}
