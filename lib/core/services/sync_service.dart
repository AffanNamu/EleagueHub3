import 'dart:async';
import 'package:flutter/foundation.dart';

import '../database/db_helper.dart';
import 'connectivity_service.dart';

/// Handles bidirectional sync between local DB and cloud
/// Offline-first, safe, and auto-syncs on reconnection
class SyncService {
  SyncService._internal();

  static final SyncService instance = SyncService._internal();

  final DbHelper _dbHelper = DbHelper.instance;
  final ConnectivityService _connectivity =
      ConnectivityService.instance;

  bool _isSyncing = false;
  StreamSubscription<bool>? _connectionSub;

  /// Must be called once (e.g. in main.dart)
  void initialize() {
    // Auto-sync when internet becomes available
    _connectionSub =
        _connectivity.connectionStream.listen((isOnline) {
      if (isOnline) {
        syncAll();
      }
    });
  }

  /// Push local unsynced changes to the cloud
  Future<void> syncLocalToCloud() async {
    if (_isSyncing) return;

    final online = await _connectivity.recheckConnection();
    if (!online) return;

    _isSyncing = true;

    try {
      final db = await _dbHelper.database;

      final unsyncedMatches = await db.query(
        'matches',
        where: 'isSynced = ?',
        whereArgs: [0],
      );

      if (unsyncedMatches.isEmpty) return;

      debugPrint(
        'SyncService → ${unsyncedMatches.length} local changes to upload',
      );

      for (final match in unsyncedMatches) {
        try {
          // TODO: Replace with real cloud upload
          // await cloudClient.upsertMatch(match);

          debugPrint(
            'SyncService → Uploading match ${match['id']}',
          );

          await db.update(
            'matches',
            {
              'isSynced': 1,
              'lastSyncedAt':
                  DateTime.now().millisecondsSinceEpoch,
            },
            where: 'id = ?',
            whereArgs: [match['id']],
          );
        } catch (e) {
          debugPrint(
            'SyncService → Failed to sync match ${match['id']}: $e',
          );
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Pull new cloud data into local database
  Future<void> syncCloudToLocal() async {
    final online = await _connectivity.recheckConnection();
    if (!online) return;

    try {
      debugPrint(
        'SyncService → Pulling latest data from cloud',
      );

      // TODO:
      // 1. Fetch updated records since lastSync
      // 2. Resolve conflicts (admin wins)
      // 3. Upsert into local DB

    } catch (e) {
      debugPrint(
        'SyncService → Cloud pull failed: $e',
      );
    }
  }

  /// Safe full sync (can be called many times)
  Future<void> syncAll() async {
    if (_isSyncing) return;

    debugPrint('SyncService → Starting full sync');

    await syncLocalToCloud();
    await syncCloudToLocal();
  }

  void dispose() {
    _connectionSub?.cancel();
    _connectionSub = null;
  }
}
