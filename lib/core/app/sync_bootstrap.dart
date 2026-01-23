import '../services/connectivity_service.dart';
import '../services/sync_service.dart';

class SyncBootstrap {
  static Future<void> init() async {
    await ConnectivityService.instance.initialize();

    // try once on startup (non-fatal)
    try {
      await SyncService.instance.syncAll();
    } catch (_) {}

    // sync when internet comes back (non-fatal)
    ConnectivityService.instance.connectionStream.listen((online) async {
      if (!online) return;
      try {
        await SyncService.instance.syncAll();
      } catch (_) {}
    });
  }
}
