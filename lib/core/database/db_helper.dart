/// ONLINE-ONLY MIGRATION (Facebook/X style)
///
/// Legacy local SQLite helper (sqflite) used for offline-first flows.
///
/// Online-only rules require removing local persistence. This helper is now a
/// compatibility stub so the app can compile while remaining strictly online-only.
///
/// Any attempt to use this will throw immediately.
class DbHelper {
  /// Singleton instance (kept to avoid breaking imports).
  static final DbHelper instance = DbHelper._init();

  DbHelper._init();

  Never _disabled() {
    throw UnsupportedError('Local database is disabled in online-only mode.');
  }

  /// Legacy API surface (disabled)
  Future<dynamic> get database async => _disabled();

  Future<int> insertTeam(Map<String, dynamic> row) async => _disabled();
  Future<int> insertMatch(Map<String, dynamic> row) async => _disabled();
  Future<int> insertParticipant(Map<String, dynamic> row) async => _disabled();

  Future<List<Map<String, dynamic>>> getAllTeams(String leagueId) async => _disabled();
  Future<List<Map<String, dynamic>>> getAllMatches(String leagueId) async => _disabled();
  Future<List<Map<String, dynamic>>> getAllParticipants(String leagueId) async => _disabled();

  Future<int> deleteParticipant(String leagueId, String participantId) async => _disabled();
  Future<int> markParticipantSynced(String leagueId, String participantId) async => _disabled();

  Future<void> close() async => _disabled();
}
