import 'dart:async';

import 'package:flutter/foundation.dart';

import 'connectivity_service.dart';

/// ONLINE-ONLY MIGRATION (Facebook/X style)
///
/// Legacy versions of this app implemented an offline-first sync engine:
/// - local queue -> cloud replay
/// - cloud -> local mirroring
/// - background sync on reconnect
///
/// In online-only architecture:
/// - There is no local persistence of domain data
/// - There is no offline queue
/// - There is no background sync
///
/// This class remains ONLY to keep backward compatibility with older screens
/// that call `SyncService.instance.syncAll()`.
/// It is intentionally best-effort and never throws.
class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  final ConnectivityService _connectivity = ConnectivityService.instance;

  bool _isSyncing = false;

  bool get isSyncing => _isSyncing;

  /// Backward-compatible entry point.
  ///
  /// Online-only behavior:
  /// - Optionally recheck connectivity (fast)
  /// - Do not perform any local/cloud reconciliation
  /// - Never throw (so old UIs don't get stuck)
  Future<void> syncAll({Duration timeout = const Duration(seconds: 8)}) async {
    if (_isSyncing) return;

    _isSyncing = true;
    try {
      // Keep it lightweight: a "sync" in online-only mode is effectively a connectivity recheck.
      await _connectivity.recheckConnection().timeout(timeout);
    } catch (e) {
      // Never surface raw technical errors from here.
      if (kDebugMode) {
        debugPrint('SyncService (online-only) → syncAll noop/recheck failed: $e');
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Legacy method name used by some older UI/widgets.
  /// Kept for compatibility; online-only => no-op.
  Future<void> syncLocalToCloud({Duration timeout = const Duration(seconds: 8)}) async {
    return syncAll(timeout: timeout);
  }

  /// Legacy placeholder for old flows. Online-only => no-op.
  Future<void> syncCloudToLocal({Duration timeout = const Duration(seconds: 8)}) async {
    return syncAll(timeout: timeout);
  }
}
