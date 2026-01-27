import 'dart:convert';
import 'package:http/http.dart' as http;

class LiveKitTokenResponse {
  final String token;
  final String url;
  final String roomName;
  final bool isHost;

  LiveKitTokenResponse({
    required this.token,
    required this.url,
    required this.roomName,
    required this.isHost,
  });

  factory LiveKitTokenResponse.fromJson(Map<String, dynamic> json) {
    return LiveKitTokenResponse(
      token: (json['token'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      roomName: (json['roomName'] ?? '').toString(),
      isHost: json['isHost'] == true,
    );
  }
}

class LiveKitService {
  static const String workerUrl = 'https://livekit-token-worker.esportlyic.workers.dev';

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
        'isHost': isHost,
        // keep role for backward compatibility if any older worker is deployed
        'role': isHost ? 'host' : 'listener',
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

  static Future<void> muteSpeaker({
    required String leagueId,
    required String targetUserId,
  }) async {
    final res = await http.post(
      Uri.parse('$workerUrl/admin'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'leagueId': leagueId,
        'action': 'mute',
        'targetUserId': targetUserId,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('LiveKit mute failed: ${res.body}');
    }
  }

  static Future<void> unmuteSpeaker({
    required String leagueId,
    required String targetUserId,
  }) async {
    final res = await http.post(
      Uri.parse('$workerUrl/admin'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'leagueId': leagueId,
        'action': 'unmute',
        'targetUserId': targetUserId,
      }),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('LiveKit unmute failed: ${res.body}');
    }
  }
}
