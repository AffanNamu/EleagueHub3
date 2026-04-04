import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import 'desktop_pairing_models.dart';

class DesktopPairingService {
  DesktopPairingService._();

  static final DesktopPairingService instance = DesktopPairingService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<DesktopPairingSession> createSession() async {
    final response = await _client.functions.invoke(
      'create-desktop-session',
      body: <String, dynamic>{},
    );

    final data = Map<String, dynamic>.from(response.data as Map);
    return DesktopPairingSession.fromMap(data);
  }

  Future<DesktopPairingApprovalResult> approveSession({
    required String sessionId,
    required String sessionSecret,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid.trim().isEmpty) {
      return const DesktopPairingApprovalResult(
        success: false,
        message: 'Please sign in first.',
        status: 'failed',
      );
    }

    final idToken = await user.getIdToken(true);
    if ((idToken ?? '').trim().isEmpty) {
      return const DesktopPairingApprovalResult(
        success: false,
        message: 'Could not validate your account session.',
        status: 'failed',
      );
    }

    final response = await _client.functions.invoke(
      'approve-desktop-session',
      headers: <String, String>{
        'Authorization': 'Bearer $idToken',
      },
      body: <String, dynamic>{
        'session_id': sessionId,
        'session_secret': sessionSecret,
        'paired_user_name': (user.displayName ?? '').trim(),
        'paired_user_email': (user.email ?? '').trim(),
      },
    );

    final data = Map<String, dynamic>.from(response.data as Map);
    return DesktopPairingApprovalResult.fromMap(data);
  }

  Future<DesktopPairingStatus> getStatus({
    required String sessionId,
    required String sessionSecret,
  }) async {
    final response = await _client.functions.invoke(
      'get-desktop-session-status',
      body: <String, dynamic>{
        'session_id': sessionId,
        'session_secret': sessionSecret,
      },
    );

    final data = Map<String, dynamic>.from(response.data as Map);
    return DesktopPairingStatus.fromMap(data);
  }

  bool tryParseDesktopQrPayload(
    String raw, {
    required void Function(String sessionId, String sessionSecret) onParsed,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;

    try {
      final uri = Uri.parse(trimmed);
      final scheme = uri.scheme.toLowerCase();
      final host = uri.host.toLowerCase();

      if (scheme != 'eleaguehub') return false;
      if (host != 'desktop-link') return false;

      final sessionId = (uri.queryParameters['sessionId'] ?? '').trim();
      final sessionSecret = (uri.queryParameters['sessionSecret'] ?? '').trim();

      if (sessionId.isEmpty || sessionSecret.isEmpty) return false;

      onParsed(sessionId, sessionSecret);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> initializeSupabase() async {
    SupabaseConfig.assertConfigured();
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  }
}
