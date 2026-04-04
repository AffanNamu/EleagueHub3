class WebDesktopSessionStore {
  static Future<void> save({
    required String sessionId,
    required String sessionSecret,
    required String pairedUserUid,
    required String pairedUserName,
    required String pairedUserEmail,
  }) async {}

  static Future<Map<String, String>?> load() async {
    return null;
  }

  static Future<void> clear() async {}
}
