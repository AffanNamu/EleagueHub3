import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/connectivity_service.dart';
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

  // ------------------------------------------------------
  // CREATE (local) — used by LeagueCreateWizard
  // ------------------------------------------------------

  /// Creates a league locally, generating a Join ID (code) if missing,
  /// then queues it for Firestore sync.
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

    // Upsert locally (WITHOUT calling saveLeague to avoid double-work)
    final all = await getAllLeagues();
    final idx = all.indexWhere((l) => l.id == stored.id);
    if (idx >= 0) {
      all[idx] = stored;
    } else {
      all.add(stored);
    }

    await _prefs.setStringList(
      kLeaguesKey,
      all.map((l) => l.toJsonString()).toList(),
    );

    // Queue for cloud
    await _queue.enqueue(
      id: _uuid.v4(),
      entityType: 'league',
      entityId: stored.id,
      action: 'create',
      lastModified: now,
      payload: stored.toJson(),
    );

    return stored;
  }

  // ------------------------------------------------------
  // JOIN by code (online-first, offline fallback)
  // ------------------------------------------------------

  /// Joins a league by Join ID.
  ///
  /// Online behavior:
  /// - Find league in Firestore by `code`
  /// - Add `userId` to `memberIds` (arrayUnion)
  /// - Pull league doc and store locally
  ///
  /// Offline behavior:
  /// - Create a placeholder league locally (so UI can work)
  /// - Queue a "join" action for later (we store it as a special queue item)
  ///
  /// NOTE:
  /// For the online join to work, Firestore league docs MUST store `code` and `memberIds`.
  Future<League> joinLeagueLocallyByCode({
    required String joinCode,
    required String userId,
    required League Function(String generatedLeagueId) placeholderBuilder,
  }) async {
    final code = joinCode.trim().toUpperCase();
    final now = DateTime.now().millisecondsSinceEpoch;

    // If online, join via Firestore and cache locally
    final online = ConnectivityService.instance.isConnected.value;
    if (online) {
      final firestore = FirebaseFirestore.instance;

      final query = await firestore.collection('leagues').where('code', isEqualTo: code).limit(1).get();
      if (query.docs.isEmpty) {
        throw StateError('League not found for Join ID: $code');
      }

      final doc = query.docs.first;
      final leagueId = doc.id;

      // join transaction: add memberIds
      await firestore.collection('leagues').doc(leagueId).set(
        {
          'memberIds': FieldValue.arrayUnion([userId]),
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      );

      // pull latest doc after join
      final fresh = await firestore.collection('leagues').doc(leagueId).get();
      final data = (fresh.data() ?? <String, dynamic>{});
      data['id'] = leagueId;

      final league = League.fromRemoteMap(data);

      // store locally without queueing create/update again
      await _upsertLocalNoQueue(league);

      return league;
    }

    // Offline fallback: placeholder locally
    final generatedLeagueId = _uuid.v4();
    final placeholder = placeholderBuilder(generatedLeagueId).copyWith(
      code: code,
      updatedAtMs: now,
    );

    await _upsertLocalNoQueue(placeholder);

    // Queue a special action so SyncService can process later
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

    return placeholder;
  }

  // ------------------------------------------------------
  // Helpers
  // ------------------------------------------------------

  Future<void> _upsertLocalNoQueue(League league) async {
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

  String _generateJoinCode({int length = 6}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}
