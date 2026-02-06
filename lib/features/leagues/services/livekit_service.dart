import 'dart:convert';

import 'package:http/http.dart' as http;

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

  /// Existing behavior (Spaces / league rooms): roomName = league_<leagueId>
  static Future<LiveKitTokenResponse> fetchToken({
    required String leagueId,
    required String userId,
    required bool isHost,
  }) async {
    final res = await http.post(
      Uri.parse(workerUrl),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'leagueId': leagueId,
        'userId': userId,
        // Twitter Spaces behavior: listener vs speaker is NOT a different token.
        // Everyone can publish; "listener" is simply "mic muted".
        'role': isHost ? 'host' : 'participant',
      }),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Token server error ${res.statusCode}: ${res.body}');
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final tok = LiveKitTokenResponse.fromJson(decoded);

    if (tok.token.isEmpty || tok.url.isEmpty || tok.roomName.isEmpty) {
      throw Exception('Invalid token response: ${res.body}');
    }

    return tok;
  }

  /// New behavior (Live video matches): roomName = match_<matchId>
  ///
  /// This is intentionally separate from [fetchToken] to keep Spaces behavior stable.
  static Future<LiveKitTokenResponse> fetchMatchToken({
    required String matchId,
    required String userId,
    required bool isHost,
    String? side, // optional: "home" | "away" | "unknown"
  }) async {
    final payload = <String, dynamic>{
      'matchId': matchId,
      'userId': userId,
      'role': isHost ? 'host' : 'participant',
    };

    final s = side?.trim();
    if (s != null && s.isNotEmpty) {
      payload['side'] = s;
    }

    final res = await http.post(
      Uri.parse(workerUrl),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Token server error ${res.statusCode}: ${res.body}');
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final tok = LiveKitTokenResponse.fromJson(decoded);

    if (tok.token.isEmpty || tok.url.isEmpty || tok.roomName.isEmpty) {
      throw Exception('Invalid token response: ${res.body}');
    }

    return tok;
  }

  /// New behavior (Voice room by 8-digit code): roomName = call_<callId>
  ///
  /// callId must be exactly 8 digits.
  static Future<LiveKitTokenResponse> fetchCallToken({
    required String callId,
    required String userId,
    bool isHost = false,
  }) async {
    final code = callId.trim();
    if (!RegExp(r'^\d{8}$').hasMatch(code)) {
      throw Exception('callId must be exactly 8 digits');
    }

    final res = await http.post(
      Uri.parse(workerUrl),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'callId': code,
        'userId': userId,
        'role': isHost ? 'host' : 'participant',
      }),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Token server error ${res.statusCode}: ${res.body}');
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final tok = LiveKitTokenResponse.fromJson(decoded);

    if (tok.token.isEmpty || tok.url.isEmpty || tok.roomName.isEmpty) {
      throw Exception('Invalid token response: ${res.body}');
    }

    return tok;
  }
}
