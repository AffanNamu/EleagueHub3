import 'sync_service.dart';

class SyncTrigger {
  static Future<void> trySync() async {
    try {
      await SyncService.instance.syncAll();
    } catch (_) {
      // swallow errors; UI should keep working offline
    }
  }
}
