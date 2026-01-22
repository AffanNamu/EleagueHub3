import 'package:flutter/foundation.dart';
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

  // --------------------------------------------------
  // CRUD
  // --------------------------------------------------

  Future<List<League>> getAllLeagues() async {
    final raw = _prefs.getStringList(kLeaguesKey) ?? [];
    return raw.map((e) => League.fromJsonString(e)).toList();
  }

  Future<League?> getLeagueById(String id) async {
    final all = await getAllLeagues();
    return all.firstWhere((l) => l.id == id, orElse: () => null);
  }

  Future<void> saveLeague(League league) async {
    final all = await getAllLeagues();
    final existsIndex = all.indexWhere((l) => l.id == league.id);
    if (existsIndex >= 0) {
      all[existsIndex] = league;
    } else {
      all.add(league);
    }

    final raw = all.map((l) => l.toJsonString()).toList();
    await _prefs.setStringList(kLeaguesKey, raw);

    // --------------------------------------------------
    // Add to sync queue
    // --------------------------------------------------
    await _queue.enqueue(SyncQueueItem(
      id: _uuid.v4(),
      entityType: 'league',
      entityId: league.id,
      action: existsIndex >= 0 ? SyncAction.update : SyncAction.create,
      payload: league.toJsonString(),
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> deleteLeagueCompletely(String leagueId) async {
    final all = await getAllLeagues();
    all.removeWhere((l) => l.id == leagueId);
    final raw = all.map((l) => l.toJsonString()).toList();
    await _prefs.setStringList(kLeaguesKey, raw);

    // --------------------------------------------------
    // Add delete to sync queue
    // --------------------------------------------------
    await _queue.enqueue(SyncQueueItem(
      id: _uuid.v4(),
      entityType: 'league',
      entityId: leagueId,
      action: SyncAction.delete,
      payload: null,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    ));
  }
}
