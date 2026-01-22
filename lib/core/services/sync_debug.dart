import 'package:flutter/foundation.dart';
import 'sync_queue_service.dart';
import 'sync_service.dart';

class SyncDebug {
  static final ValueNotifier<String> lastLog = ValueNotifier<String>('');

  static void log(String msg) {
    lastLog.value = msg;
    debugPrint(msg);
  }

  static Future<int> queueCount() async {
    final items = await SyncQueueService.instance.getPending();
    return items.length;
  }

  static Future<void> runSync() async {
    try {
      log('SyncDebug → syncAll() start');
      await SyncService.instance.syncAll();
      final c = await queueCount();
      log('SyncDebug → syncAll() done. queue=$c');
    } catch (e) {
      log('SyncDebug → syncAll() ERROR: $e');
      rethrow;
    }
  }
}
