import 'dart:html' as html;

class WebDesktopSessionStore {
  static const String _kSessionId = 'eh_desktop_session_id';
  static const String _kSessionSecret = 'eh_desktop_session_secret';
  static const String _kPairedUserUid = 'eh_desktop_paired_user_uid';
  static const String _kPairedUserName = 'eh_desktop_paired_user_name';
  static const String _kPairedUserEmail = 'eh_desktop_paired_user_email';

  static Future<void> save({
    required String sessionId,
    required String sessionSecret,
    required String pairedUserUid,
    required String pairedUserName,
    required String pairedUserEmail,
  }) async {
    html.window.localStorage[_kSessionId] = sessionId;
    html.window.localStorage[_kSessionSecret] = sessionSecret;
    html.window.localStorage[_kPairedUserUid] = pairedUserUid;
    html.window.localStorage[_kPairedUserName] = pairedUserName;
    html.window.localStorage[_kPairedUserEmail] = pairedUserEmail;
  }

  static Future<Map<String, String>?> load() async {
    final sessionId = html.window.localStorage[_kSessionId]?.trim() ?? '';
    final sessionSecret =
        html.window.localStorage[_kSessionSecret]?.trim() ?? '';
    final pairedUserUid =
        html.window.localStorage[_kPairedUserUid]?.trim() ?? '';

    if (sessionId.isEmpty ||
        sessionSecret.isEmpty ||
        pairedUserUid.isEmpty) {
      return null;
    }

    return <String, String>{
      'sessionId': sessionId,
      'sessionSecret': sessionSecret,
      'pairedUserUid': pairedUserUid,
      'pairedUserName': html.window.localStorage[_kPairedUserName] ?? '',
      'pairedUserEmail': html.window.localStorage[_kPairedUserEmail] ?? '',
    };
  }

  static Future<void> clear() async {
    html.window.localStorage.remove(_kSessionId);
    html.window.localStorage.remove(_kSessionSecret);
    html.window.localStorage.remove(_kPairedUserUid);
    html.window.localStorage.remove(_kPairedUserName);
    html.window.localStorage.remove(_kPairedUserEmail);
  }

  static bool get hasSession {
    final uid = html.window.localStorage[_kPairedUserUid]?.trim() ?? '';
    return uid.isNotEmpty;
  }
}
