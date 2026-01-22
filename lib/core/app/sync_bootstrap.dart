import '../services/connectivity_service.dart';
import '../services/sync_service.dart';

/// Bootstraps connectivity + syncing:
/// - starts monitoring
/// - runs sync once at startup (if online)
/// - runs sync whenever internet comes back
class SyncBootstrap {
  static Future<void> init() async {
    await ConnectivityService.instance.initialize();

    // try once on startup
    await SyncService.instance.syncAll();

    // sync when internet comes back
    ConnectivityService.instance.connectionStream.listen((online) async {
      if (online) {
        await SyncService.instance.syncAll();
      }
    });
  }
}
