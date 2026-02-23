import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SupabaseEdgeNotificationsService {
  SupabaseEdgeNotificationsService._();

  static final SupabaseEdgeNotificationsService instance = SupabaseEdgeNotificationsService._();

  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  Uri? _edgeUri(String fnName) {
    final base = _supabaseUrl.trim();
    if (base.isEmpty) return null;
    final normalized = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return Uri.parse('$normalized/functions/v1/$fnName');
  }

  Future<void> notifyLeagueChatMessage({
    required String leagueId,
    required String leagueName,
    required String messageId,
    required String senderId,
    required String senderName,
    required String preview,
  }) async {
    final uri = _edgeUri('league-chat-notify');
    if (uri == null) return;

    final anon = _supabaseAnonKey.trim();
    if (anon.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = (await user.getIdToken())?.trim() ?? '';
    if (token.isEmpty) return;

    try {
      final resp = await http.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'apikey': anon,
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(<String, dynamic>{
          'leagueId': leagueId.trim(),
          'leagueName': leagueName.trim(),
          'messageId': messageId.trim(),
          'senderId': senderId.trim(),
          'senderName': senderName.trim(),
          'preview': preview.trim(),
        }),
      );

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint('Supabase notify failed: ${resp.statusCode} ${resp.body}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Supabase notify exception: $e');
      }
    }
  }
}
