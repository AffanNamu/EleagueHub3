import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// User-safe exception: if UI accidentally shows `$e`, it will still be a friendly message.
class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

class LiveKitTokenResponse {
  final String token;
  final String url;
  final String roomName;

  LiveKitTokenResponse({
    required this.token,
    required this.url,
    required this.roomName,
  });

  factory LiveKitTokenResponse.fromJson(Map<String, dynamic> json) {
    return LiveKitTokenResponse(
      token: (json['token'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      roomName: (json['roomName'] ?? '').toString(),
    );
  }
}

class LiveKitService {
  static const String workerUrl = 'https://livekit-token-worker.esportlyic.workers.dev';

  static const Duration _requestTimeout = Duration(seconds: 12);

  static Never _throwFriendlyFrom(Object error) {
    if (error is UserFriendlyException) throw error;

    if (error is SocketException) {
      throw const UserFriendlyException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    }
    if (error is TimeoutException) {
      throw const UserFriendlyException('Your internet connection seems unstable. Please try again.');
    }

    // Default: do not leak technical details.
    throw const UserFriendlyException("We couldn't connect right now. Please try again.");
  }

  static Future<Map<String, dynamic>> _postJson(
    Uri url,
    Map<String, dynamic> body, {
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    try {
      final res = await c
          .post(
            url,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);

      if (res.statusCode < 200 || res.statusCode >= 300) {
        // Never surface status/body to UI.
        throw const UserFriendlyException("We couldn't start Live right now. Please try again.");
      }

      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();

      throw const UserFriendlyException("We couldn't start Live right now. Please try again.");
    } on UserFriendlyException {
      rethrow;
    } catch (e) {
      _throwFriendlyFrom(e is Object ? e : Exception('unknown'));
    } finally {
      if (client == null) c.close();
    }
  }

  static LiveKitTokenResponse _parseTokenResponse(Map<String, dynamic> decoded) {
    try {
      final tok = LiveKitTokenResponse.fromJson(decoded);
      if (tok.token.trim().isEmpty || tok.url.trim().isEmpty || tok.roomName.trim().isEmpty) {
        throw const UserFriendlyException("We couldn't start Live right now. Please try again.");
      }
      return tok;
    } on UserFriendlyException {
      rethrow;
    } catch (e) {
      _throwFriendlyFrom(e is Object ? e : Exception('unknown'));
    }
  }

  /// Existing behavior (Spaces / league rooms): roomName = league_<leagueId>
  static Future<LiveKitTokenResponse> fetchToken({
    required String leagueId,
    required String userId,
    required bool isHost,
  }) async {
    final lid = leagueId.trim();
    final uid = userId.trim();
    if (lid.isEmpty || uid.isEmpty) {
      throw const UserFriendlyException('Please sign in and try again.');
    }

    try {
      final decoded = await _postJson(
        Uri.parse(workerUrl),
        {
          'leagueId': lid,
          'userId': uid,
          // Twitter Spaces behavior: listener vs speaker is NOT a different token.
          // Everyone can publish; "listener" is simply "mic muted".
          'role': isHost ? 'host' : 'participant',
        },
      );

      return _parseTokenResponse(decoded);
    } catch (e) {
      _throwFriendlyFrom(e is Object ? e : Exception('unknown'));
    }
  }

  /// New behavior (Live video matches): roomName = match_<matchId>
  static Future<LiveKitTokenResponse> fetchMatchToken({
    required String matchId,
    required String userId,
    required bool isHost,
    String? side, // optional: "home" | "away" | "unknown"
  }) async {
    final mid = matchId.trim();
    final uid = userId.trim();
    if (mid.isEmpty || uid.isEmpty) {
      throw const UserFriendlyException('Please sign in and try again.');
    }

    final payload = <String, dynamic>{
      'matchId': mid,
      'userId': uid,
      'role': isHost ? 'host' : 'participant',
    };

    final s = side?.trim();
    if (s != null && s.isNotEmpty) payload['side'] = s;

    try {
      final decoded = await _postJson(Uri.parse(workerUrl), payload);
      return _parseTokenResponse(decoded);
    } catch (e) {
      _throwFriendlyFrom(e is Object ? e : Exception('unknown'));
    }
  }

  /// New behavior (Voice room by 8-digit code): roomName = call_<callId>
  static Future<LiveKitTokenResponse> fetchCallToken({
    required String callId,
    required String userId,
    bool isHost = false,
  }) async {
    final code = callId.trim();
    final uid = userId.trim();
    if (uid.isEmpty) {
      throw const UserFriendlyException('Please sign in and try again.');
    }
    if (!RegExp(r'^\d{8}$').hasMatch(code)) {
      throw const UserFriendlyException('Please enter a valid call code.');
    }

    try {
      final decoded = await _postJson(
        Uri.parse(workerUrl),
        {
          'callId': code,
          'userId': uid,
          'role': isHost ? 'host' : 'participant',
        },
      );

      return _parseTokenResponse(decoded);
    } catch (e) {
      _throwFriendlyFrom(e is Object ? e : Exception('unknown'));
    }
  }
}
