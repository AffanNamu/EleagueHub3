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
  static const String workerUrl =
      'https://livekit-token-worker.esportlyic.workers.dev';

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
}
