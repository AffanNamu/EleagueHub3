import 'dart:html' as html;

import 'package:firebase_auth/firebase_auth.dart';

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
    final firebaseUser = FirebaseAuth.instance.currentUser;

    final storedSessionId = html.window.localStorage[_kSessionId]?.trim() ?? '';
    final storedSessionSecret = html.window.localStorage[_kSessionSecret]?.trim() ?? '';
    final storedUid = html.window.localStorage[_kPairedUserUid]?.trim() ?? '';

    // If localStorage says a session exists but FirebaseAuth is not signed in,
    // this is a broken/expired session (commonly caused by custom-token sign-in failure).
    // Clear it so the gate shows the login/pairing screen again.
    if (firebaseUser == null) {
      if (storedUid.isNotEmpty || storedSessionId.isNotEmpty || storedSessionSecret.isNotEmpty) {
        await clear();
      }
      return null;
    }

    final uid = firebaseUser.uid.trim();
    if (uid.isEmpty) {
      await clear();
      return null;
    }

    final name = (firebaseUser.displayName ?? '').trim();
    final email = (firebaseUser.email ?? '').trim();

    // If localStorage is missing or mismatched, rebuild it from FirebaseAuth.
    final needsRebuild = storedUid.isEmpty || storedUid != uid;

    final effectiveSessionId = (storedSessionId.isNotEmpty) ? storedSessionId : 'firebase-auth';
    final effectiveSessionSecret = (storedSessionSecret.isNotEmpty) ? storedSessionSecret : 'firebase-auth';

    if (needsRebuild) {
      await save(
        sessionId: effectiveSessionId,
        sessionSecret: effectiveSessionSecret,
        pairedUserUid: uid,
        pairedUserName: name,
        pairedUserEmail: email,
      );
    }

    return <String, String>{
      'sessionId': effectiveSessionId,
      'sessionSecret': effectiveSessionSecret,
      'pairedUserUid': uid,
      'pairedUserName': name,
      'pairedUserEmail': email,
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
    // On web, session should be tied to FirebaseAuth.
    final u = FirebaseAuth.instance.currentUser;
    return u != null && (u.uid.trim().isNotEmpty);
  }
}
