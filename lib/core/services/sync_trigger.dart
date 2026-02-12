import 'dart:async';

import 'connectivity_service.dart';

class SyncTrigger {
  /// ONLINE-ONLY (Facebook/X style):
  /// There is no local queue and no background sync.
  ///
  /// This method remains only for backward compatibility with older UI flows
  /// that "trigger sync". It performs a quick connectivity recheck and then
  /// returns without throwing.
  static Future<void> trySync({Duration timeout = const Duration(seconds: 8)}) async {
    try {
      await ConnectivityService.instance.recheckConnection().timeout(timeout);
    } catch (_) {
      // Intentionally swallow: callers should not block UI on "sync" in online-only mode.
    }
  }
}
