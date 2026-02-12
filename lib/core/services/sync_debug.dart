import 'package:flutter/foundation.dart';

/// ONLINE-ONLY MIGRATION
///
/// Legacy builds contained offline-first sync debug tooling (queue inspection,
/// conflict debugging, etc.).
///
/// Online-only architecture has:
/// - no local queue
/// - no background sync
/// - no local-vs-cloud conflict resolution layer
///
/// This file remains as a lightweight, safe diagnostics hook to avoid breaking
/// any older imports. It does NOT implement any sync behavior.
class SyncDebug {
  SyncDebug._();

  /// A simple status line that UI/debug screens may display.
  static final ValueNotifier<String> status = ValueNotifier<String>('Online-only mode');

  static void setStatus(String value) {
    status.value = value;
  }

  /// Optional debug log buffer for screens that render sync logs.
  static final ValueNotifier<List<String>> logs = ValueNotifier<List<String>>(<String>[]);

  static void log(String message) {
    // Keep the buffer bounded.
    final next = List<String>.from(logs.value);
    next.add(message);
    if (next.length > 200) {
      next.removeRange(0, next.length - 200);
    }
    logs.value = next;
  }

  static void clear() {
    logs.value = <String>[];
    status.value = 'Online-only mode';
  }
}
