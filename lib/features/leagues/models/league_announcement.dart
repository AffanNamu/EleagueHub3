import 'dart:convert';

class LeagueAnnouncement {
  final String id;
  final String leagueId;
  final String title;
  final String message;
  final int createdAtMs;

  const LeagueAnnouncement({
    required this.id,
    required this.leagueId,
    required this.title,
    required this.message,
    required this.createdAtMs,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'leagueId': leagueId,
        'title': title,
        'message': message,
        'createdAtMs': createdAtMs,
      };

  static LeagueAnnouncement fromMap(Map<String, dynamic> map) {
    return LeagueAnnouncement(
      id: map['id'] as String,
      leagueId: map['leagueId'] as String,
      title: map['title'] as String,
      message: map['message'] as String,
      createdAtMs: (map['createdAtMs'] as num).toInt(),
    );
  }

  String toJson() => jsonEncode(toMap());

  static LeagueAnnouncement fromJson(String json) {
    return fromMap(jsonDecode(json) as Map<String, dynamic>);
  }
}
