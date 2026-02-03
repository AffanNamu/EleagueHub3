import 'dart:async';

import 'sync_service.dart';

class SyncTrigger {
  /// Best-effort sync helper.
  /// Never throws and never blocks UI indefinitely.
  static Future<void> trySync({Duration timeout = const Duration(seconds: 25)}) async {
    try {
      await SyncService.instance.syncAll().timeout(timeout);
    } catch (_) {
      // swallow errors; UI should keep working offline
    }
  }
}
