/// ONLINE-ONLY MIGRATION (Facebook/X style)
///
/// The legacy app shipped an offline-first sync engine:
/// - Sync on startup
/// - Sync on reconnect
/// - Local queue → cloud replay
/// - Cloud → local mirroring
///
/// In online-only architecture, this bootstrap must do nothing.
/// All reads/writes must be live against Firebase, and failures must be handled
/// at the point of user action with friendly messaging.
class SyncBootstrap {
  static Future<void> init() async {
    // Intentionally no-op in online-only mode.
  }
}
