import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';

class SupabaseEdgeNotificationsService {
  SupabaseEdgeNotificationsService._();

  static final SupabaseEdgeNotificationsService instance =
      SupabaseEdgeNotificationsService._();

  static const String _supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: SupabaseConfig.url,
  );

  static const String _supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: SupabaseConfig.anonKey,
  );

  Uri? _edgeUri(String fnName) {
    final base = _supabaseUrl.trim();
    if (base.isEmpty) return null;
    final normalized =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
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

    final token = (await user.getIdToken()).toString().trim();
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
          debugPrint(
            'Supabase notify failed: ${resp.statusCode} ${resp.body}',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Supabase notify exception: $e');
      }
    }
  }

  Future<void> notifyFollowedOrganizerUpdate({
    required String masterLeagueId,
    required String organizerName,
    required String title,
    required String message,
    required String route,
    required String eventType,
    required String actorId,
  }) async {
    final uri = _edgeUri('organizer-follow-notify');
    if (uri == null) return;

    final anon = _supabaseAnonKey.trim();
    if (anon.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = (await user.getIdToken()).toString().trim();
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
          'masterLeagueId': masterLeagueId.trim(),
          'organizerName': organizerName.trim(),
          'title': title.trim(),
          'message': message.trim(),
          'route': route.trim(),
          'eventType': eventType.trim(),
          'actorId': actorId.trim(),
        }),
      );

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint(
            'Organizer follow notify failed: ${resp.statusCode} ${resp.body}',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Organizer follow notify exception: $e');
      }
    }
  }
}
