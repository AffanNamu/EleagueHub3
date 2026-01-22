import 'dart:async';
import 'package:flutter/foundation.dart';

import 'connectivity_service.dart';
import 'sync_queue_service.dart';

/// Handles bidirectional sync between local data and cloud
/// Offline-first, queue-based, backend-agnostic
class SyncService {
  SyncService._internal();

  static final SyncService instance = SyncService._internal();

  final ConnectivityService _connectivity =
      ConnectivityService.instance;

  bool _isSyncing = false;

  /// Main entry point (safe to call repeatedly)
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

    debugPrint(
      'SyncService → Syncing ${queue.length} queued changes',
    );

    for (final item in queue) {
      try {
        await _uploadItem(item);

        // Mark as done ONLY after success
        await SyncQueueService.instance.markDone(item.id);

        debugPrint(
          'SyncService → Synced ${item.entityType}:${item.entityId}',
        );
      } catch (e) {
        debugPrint(
          'SyncService → Failed ${item.entityType}:${item.entityId} → $e',
        );

        // Stop on failure to preserve order & consistency
        break;
      }
    }
  }

  /// Upload a single queued item to the backend
  /// Replace body when backend is ready
  Future<void> _uploadItem(SyncQueueItem item) async {
    // TODO: Replace with real backend logic
    // Examples:
    // - Supabase upsert
    // - Firebase set/update/delete
    // - REST POST/PUT/DELETE

    debugPrint(
      'Uploading → '
      '${item.entityType} | '
      '${item.action} | '
      'id=${item.entityId}',
    );

    // Simulated latency
    await Future.delayed(const Duration(milliseconds: 300));
  }

  // --------------------------------------------------
  // CLOUD → LOCAL (stub)
  // --------------------------------------------------

  Future<void> _syncCloudToLocal() async {
    if (!_connectivity.isConnected.value) return;

    // TODO: Implement when backend exists
    // Strategy:
    // - Pull changes newer than lastPulledAt
    // - Compare timestamps
    // - Merge safely

    debugPrint('SyncService → Cloud pull skipped (not configured)');
  }
}
