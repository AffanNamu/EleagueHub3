/// ONLINE-ONLY MIGRATION (Facebook/X style)
///
/// This project previously contained a local database (Drift/SQLite) for offline-first flows.
/// Online-only rules require:
/// - No local persistence
/// - No background sync
/// - No local caching layer
///
/// This file is intentionally reduced to a compatibility stub to:
/// - prevent accidental local persistence
/// - avoid hard dependency on Drift packages
///
/// If any code path still tries to use AppDatabase, it will fail fast.
class AppDatabase {
  AppDatabase() {
    throw UnsupportedError(
      'Local database is disabled in online-only mode.',
    );
  }
}
