import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'connectivity_service.dart';
import 'sync_queue_service.dart';

class SyncService {
  SyncService._internal();

  static final SyncService instance = SyncService._internal();

  final ConnectivityService _connectivity = ConnectivityService.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isSyncing = false;

  Future<void> syncAll() async {
    if (_isSyncing) return;

    await _connectivity.recheckConnection();
    if (!_connectivity.isConnected.value) {
      debugPrint('SyncService → Not syncing (offline)');
      return;
    }

    _isSyncing = true;
    try {
      await _syncLocalQueueToCloud();

      // Cloud pull still disabled until we add safe queries + indexes
      debugPrint('SyncService → Cloud pull skipped (temporary)');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncLocalQueueToCloud() async {
    final queue = await SyncQueueService.instance.getPending();

    debugPrint('SyncService → Pending queue items: ${queue.length}');
    for (final q in queue) {
      debugPrint('QueueItem → type=${q.entityType} action=${q.action} entityId=${q.entityId}');
    }

    if (queue.isEmpty) {
      debugPrint('SyncService → No pending local changes');
      return;
    }

    for (final item in queue) {
      try {
        await _uploadItem(item);
        await SyncQueueService.instance.markDone(item.id);
        debugPrint('SyncService → Synced ${item.entityType}:${item.entityId}');
      } catch (e, st) {
        debugPrint('SyncService → FAILED item ${item.entityType}:${item.entityId} → $e');
        debugPrint('$st');
        rethrow;
      }
    }
  }

  Future<void> _uploadItem(SyncQueueItem item) async {
    if (!_connectivity.isConnected.value) return;

    switch (item.entityType) {
      case 'league':
        await _uploadLeague(item);
        return;

      case 'league_join':
        await _uploadLeagueJoin(item);
        return;

      case 'membership':
        await _uploadMembership(item);
        return;

      case 'teams_replace':
        await _uploadTeamsReplace(item);
        return;

      case 'matches_replace':
        await _uploadMatchesReplace(item);
        return;

      case 'matches_upsert':
        await _uploadMatchesUpsert(item);
        return;

      case 'knockout_replace':
        await _uploadKnockoutReplace(item);
        return;

      default:
        debugPrint('SyncService → Unknown entityType=${item.entityType} (skipped)');
        return;
    }
  }

  // -----------------------
  // LEAGUE
  // -----------------------

  Future<void> _uploadLeague(SyncQueueItem item) async {
    final ref = _firestore.collection('leagues').doc(item.entityId);

    if (item.action == 'delete') {
      await ref.delete();
      return;
    }

    final payload = item.payload;
    if (payload == null) {
      throw StateError('Missing payload for ${item.action} on league ${item.entityId}');
    }

    final data = Map<String, dynamic>.from(payload);

    data['id'] = item.entityId;

    final ownerId = (data['organizerUserId'] as String?) ?? '';
    data['ownerId'] = ownerId;

    final isPrivate = data['isPrivate'] == 1 || data['isPrivate'] == true;
    data['isPrivate'] = isPrivate;

    final existing = (data['memberIds'] as List?)?.cast<dynamic>() ?? const [];
    final memberIds = <String>{
      ...existing.map((e) => e.toString()),
      if (ownerId.isNotEmpty) ownerId,
    }.toList();
    data['memberIds'] = memberIds;

    await ref.set(data, SetOptions(merge: true));
  }

  // -----------------------
  // JOIN
  // -----------------------

  Future<void> _uploadLeagueJoin(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for league_join');

    final code = (payload['code'] as String?)?.trim().toUpperCase();
    final userId = (payload['userId'] as String?)?.trim();
    if (code == null || code.isEmpty || userId == null || userId.isEmpty) {
      throw StateError('Invalid payload for league_join: $payload');
    }

    final snap = await _firestore.collection('leagues').where('code', isEqualTo: code).limit(1).get();
    if (snap.docs.isEmpty) throw StateError('League not found for Join ID: $code');

    final leagueId = snap.docs.first.id;

    await _firestore.collection('leagues').doc(leagueId).set(
      {
        'memberIds': FieldValue.arrayUnion([userId]),
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      },
      SetOptions(merge: true),
    );
  }

  // -----------------------
  // MEMBERSHIP
  // -----------------------

  Future<void> _uploadMembership(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for membership');

    final leagueId = payload['leagueId'] as String?;
    if (leagueId == null || leagueId.isEmpty) {
      throw StateError('membership payload missing leagueId');
    }

    final doc = _firestore.collection('leagues').doc(leagueId).collection('memberships').doc(item.entityId);

    if (item.action == 'delete') {
      await doc.delete();
      return;
    }

    await doc.set(payload, SetOptions(merge: true));
  }

  // -----------------------
  // TEAMS REPLACE
  // -----------------------

  Future<void> _uploadTeamsReplace(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for teams_replace');

    final leagueId = payload['leagueId'] as String?;
    final teams = payload['teams'] as List<dynamic>?;
    if (leagueId == null || leagueId.isEmpty || teams == null) {
      throw StateError('teams_replace payload invalid');
    }

    final batch = _firestore.batch();
    final col = _firestore.collection('leagues').doc(leagueId).collection('teams');

    // Upsert all teams provided
    for (final t in teams) {
      final map = (t as Map).cast<String, dynamic>();
      final id = map['id'] as String;
      batch.set(col.doc(id), map, SetOptions(merge: true));
    }

    await batch.commit();
  }

  // -----------------------
  // MATCHES REPLACE
  // -----------------------

  Future<void> _uploadMatchesReplace(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for matches_replace');

    final leagueId = payload['leagueId'] as String?;
    final matches = payload['matches'] as List<dynamic>?;
    if (leagueId == null || leagueId.isEmpty || matches == null) {
      throw StateError('matches_replace payload invalid');
    }

    final col = _firestore.collection('leagues').doc(leagueId).collection('matches');

    // Batch writes are limited (500 ops). Chunk safely.
    await _batchUpsertList(
      col: col,
      items: matches,
      idKey: 'id',
    );
  }

  // -----------------------
  // MATCHES UPSERT
  // -----------------------

  Future<void> _uploadMatchesUpsert(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for matches_upsert');

    final leagueId = payload['leagueId'] as String?;
    final matches = payload['matches'] as List<dynamic>?;
    if (leagueId == null || leagueId.isEmpty || matches == null) {
      throw StateError('matches_upsert payload invalid');
    }

    final col = _firestore.collection('leagues').doc(leagueId).collection('matches');

    await _batchUpsertList(
      col: col,
      items: matches,
      idKey: 'id',
    );
  }

  // -----------------------
  // KNOCKOUT REPLACE
  // -----------------------

  Future<void> _uploadKnockoutReplace(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) throw StateError('Missing payload for knockout_replace');

    final leagueId = payload['leagueId'] as String?;
    final matches = payload['matches'] as List<dynamic>?;
    if (leagueId == null || leagueId.isEmpty || matches == null) {
      throw StateError('knockout_replace payload invalid');
    }

    final col = _firestore.collection('leagues').doc(leagueId).collection('knockout');

    await _batchUpsertList(
      col: col,
      items: matches,
      idKey: 'id',
    );
  }

  // -----------------------
  // Helpers
  // -----------------------

  Future<void> _batchUpsertList({
    required CollectionReference<Map<String, dynamic>> col,
    required List<dynamic> items,
    required String idKey,
  }) async {
    const chunkSize = 450; // keep under 500 safely
    for (var i = 0; i < items.length; i += chunkSize) {
      final chunk = items.sublist(i, (i + chunkSize > items.length) ? items.length : i + chunkSize);
      final batch = _firestore.batch();
      for (final it in chunk) {
        final map = (it as Map).cast<String, dynamic>();
        final id = map[idKey] as String;
        batch.set(col.doc(id), map, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }
}
