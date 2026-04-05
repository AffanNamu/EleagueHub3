import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import 'desktop_pairing_models.dart';

class DesktopPairingService {
  DesktopPairingService._();

  static final DesktopPairingService instance = DesktopPairingService._();

  SupabaseClient get _client => Supabase.instance.client;

  String _bestErrorMessage(Object e) {
    final raw = e.toString().trim();
    if (raw.isEmpty) {
      return 'Something went wrong. Please try again.';
    }

    var msg = raw;

    msg = msg.replaceFirst('Exception: ', '');
    msg = msg.replaceFirst('Bad state: ', '');
    msg = msg.replaceFirst('StateError: ', '');

    if (msg.contains('FunctionsException')) {
      return raw;
    }

    return msg;
  }

  Future<DesktopPairingSession> createSession() async {
    try {
      final response = await _client.functions.invoke(
        'create-desktop-session',
        body: <String, dynamic>{},
      );

      final dataRaw = response.data;
      if (dataRaw is! Map) {
        throw StateError('Create session failed: invalid server response.');
      }

      final data = Map<String, dynamic>.from(dataRaw);
      return DesktopPairingSession.fromMap(data);
    } catch (e) {
      throw StateError(_bestErrorMessage(e));
    }
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

    try {
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

      final dataRaw = response.data;
      if (dataRaw is! Map) {
        throw StateError('Desktop approval failed: invalid server response.');
      }

      final data = Map<String, dynamic>.from(dataRaw);
      return DesktopPairingApprovalResult.fromMap(data);
    } catch (e) {
      throw StateError(_bestErrorMessage(e));
    }
  }

  Future<DesktopPairingStatus> getStatus({
    required String sessionId,
    required String sessionSecret,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'get-desktop-session-status',
        body: <String, dynamic>{
          'session_id': sessionId,
          'session_secret': sessionSecret,
        },
      );

      final dataRaw = response.data;
      if (dataRaw is! Map) {
        throw StateError('Status check failed: invalid server response.');
      }

      final data = Map<String, dynamic>.from(dataRaw);
      return DesktopPairingStatus.fromMap(data);
    } catch (e) {
      throw StateError(_bestErrorMessage(e));
    }
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
