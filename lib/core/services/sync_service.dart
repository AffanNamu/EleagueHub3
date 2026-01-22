import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../features/leagues/data/leagues_repository_local.dart';
import '../../features/leagues/models/league.dart';
import '../persistence/prefs_service.dart';
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
    if (!_connectivity.isConnected.value) return;

    _isSyncing = true;
    try {
      await _syncLocalQueueToCloud();
      await _syncCloudToLocal();
    } finally {
      _isSyncing = false;
    }
  }

  // --------------------------------------------------
  // LOCAL → CLOUD
  // --------------------------------------------------

  Future<void> _syncLocalQueueToCloud() async {
    final queue = await SyncQueueService.instance.getPending();

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
        break; // preserve order
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
        throw UnsupportedError('No uploader for entityType=${item.entityType}');
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

    // Normalize organizer fields
    final ownerId = (data['organizerUserId'] as String?) ?? '';
    data['ownerId'] = ownerId;

    // Privacy helper: Firestore uses isPrivate for now
    final isPrivate = data['isPrivate'] == 1 || data['isPrivate'] == true;
    data['isPrivate'] = isPrivate;

    // Ensure memberIds exists (owner is always a member)
    final existing = (data['memberIds'] as List?)?.cast<dynamic>() ?? const [];
    final memberIds = <String>{
      ...existing.map((e) => e.toString()),
      if (ownerId.isNotEmpty) ownerId,
    }.toList();
    data['memberIds'] = memberIds;

    await ref.set(data, SetOptions(merge: true));
  }

  /// Process queued offline "join by code".
  ///
  /// payload must contain:
  /// - code: String
  /// - userId: String
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

    // Find league by code then add userId to memberIds.
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

    // Optional improvement (not required): you could also fetch the league doc
    // and overwrite the local placeholder here. We can add that next.
  }

  // --------------------------------------------------
  // CLOUD → LOCAL
  // --------------------------------------------------

  Future<void> _syncCloudToLocal() async {
    if (!_connectivity.isConnected.value) return;

    final prefs = await PreferencesService.create();
    final localLeagues = LocalLeaguesRepository(prefs);

    final currentUserId = prefs.getCurrentUserId() ?? 'admin_user';
    final lastPulledAtMs = prefs.getInt('leagues_last_pulled_at_ms') ?? 0;

    debugPrint('SyncService → Pulling leagues updated after $lastPulledAtMs for user=$currentUserId');

    // Two queries:
    // 1) Public leagues
    // 2) Leagues where I'm a member
    final qPublic = _firestore
        .collection('leagues')
        .where('isPrivate', isEqualTo: false)
        .where('updatedAtMs', isGreaterThan: lastPulledAtMs)
        .orderBy('updatedAtMs', descending: false)
        .limit(500);

    final qMember = _firestore
        .collection('leagues')
        .where('memberIds', arrayContains: currentUserId)
        .where('updatedAtMs', isGreaterThan: lastPulledAtMs)
        .orderBy('updatedAtMs', descending: false)
        .limit(500);

    final results = await Future.wait([qPublic.get(), qMember.get()]);

    final allDocs = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snap in results) {
      for (final doc in snap.docs) {
        allDocs[doc.id] = doc;
      }
    }

    if (allDocs.isEmpty) {
      debugPrint('SyncService → No new leagues from cloud');
      return;
    }

    int newest = lastPulledAtMs;

    for (final doc in allDocs.values) {
      final data = doc.data();
      data['id'] = doc.id;

      final league = League.fromRemoteMap(data);

      await _upsertLeagueLocallyWithoutQueue(prefs, league);

      if (league.updatedAtMs > newest) newest = league.updatedAtMs;
    }

    await prefs.setInt('leagues_last_pulled_at_ms', newest);

    // keep analyzer happy (and ensures local repo is referenced)
    await localLeagues.getAllLeagues();

    debugPrint('SyncService → Pulled ${allDocs.length} leagues. New lastPulled=$newest');
  }

  Future<void> _upsertLeagueLocallyWithoutQueue(
    PreferencesService prefs,
    League league,
  ) async {
    const key = LocalLeaguesRepository.kLeaguesKey;

    final raw = prefs.getStringList(key) ?? [];
    final leagues = raw.map((e) => League.fromJsonString(e)).toList();

    final idx = leagues.indexWhere((l) => l.id == league.id);
    if (idx >= 0) {
      if (league.updatedAtMs >= leagues[idx].updatedAtMs) {
        leagues[idx] = league;
      }
    } else {
      leagues.add(league);
    }

    await prefs.setStringList(key, leagues.map((l) => l.toJsonString()).toList());
  }
}
