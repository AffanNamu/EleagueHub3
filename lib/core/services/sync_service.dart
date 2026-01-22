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

      // Keep disabled until you finalize list rules/indexes
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

    debugPrint('SyncService → Syncing ${queue.length} queued changes');

    for (final item in queue) {
      try {
        await _uploadItem(item);
        await SyncQueueService.instance.markDone(item.id);
        debugPrint('SyncService → Synced ${item.entityType}:${item.entityId}');
      } catch (e, st) {
        debugPrint('SyncService → Failed ${item.entityType}:${item.entityId} → $e');
        debugPrint('$st');
        break;
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

      default:
        debugPrint('SyncService → Skipping unsupported entityType=${item.entityType}');
        return;
    }
  }

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

    // Ensure Firestore doc has id field (your fromRemoteMap expects it)
    data['id'] = item.entityId;

    // Ensure memberIds exists (owner is always a member)
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

    debugPrint('SyncService → Writing league to Firestore doc=${item.entityId}');
    await ref.set(data, SetOptions(merge: true));
  }

  Future<void> _uploadLeagueJoin(SyncQueueItem item) async {
    final payload = item.payload;
    if (payload == null) {
      throw StateError('Missing payload for league_join');
    }

    final code = (payload['code'] as String?)?.trim().toUpperCase();
    final userId = (payload['userId'] as String?)?.trim();

    if (code == null || code.isEmpty || userId == null || userId.isEmpty) {
      throw StateError('Invalid payload for league_join: $payload');
    }

    final snap = await _firestore.collection('leagues').where('code', isEqualTo: code).limit(1).get();
    if (snap.docs.isEmpty) {
      throw StateError('League not found for Join ID: $code');
    }

    final doc = snap.docs.first;
    await _firestore.collection('leagues').doc(doc.id).set(
      {
        'memberIds': FieldValue.arrayUnion([userId]),
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      },
      SetOptions(merge: true),
    );
  }
}
