import 'dart:convert';

class LeagueAnnouncement {
  final String id;
  final String leagueId;
  final String title;
  final String message;
  final int createdAtMs;
  final String authorId;
  final String authorName;
  final String scope;
  final String masterLeagueId;
  final bool pinned;
  final int pinnedAtMs;
  final String pinnedBy;

  const LeagueAnnouncement({
    required this.id,
    required this.leagueId,
    required this.title,
    required this.message,
    required this.createdAtMs,
    this.authorId = '',
    this.authorName = '',
    this.scope = 'league',
    this.masterLeagueId = '',
    this.pinned = false,
    this.pinnedAtMs = 0,
    this.pinnedBy = '',
  });

  LeagueAnnouncement copyWith({
    String? id,
    String? leagueId,
    String? title,
    String? message,
    int? createdAtMs,
    String? authorId,
    String? authorName,
    String? scope,
    String? masterLeagueId,
    bool? pinned,
    int? pinnedAtMs,
    String? pinnedBy,
  }) {
    return LeagueAnnouncement(
      id: id ?? this.id,
      leagueId: leagueId ?? this.leagueId,
      title: title ?? this.title,
      message: message ?? this.message,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      scope: scope ?? this.scope,
      masterLeagueId: masterLeagueId ?? this.masterLeagueId,
      pinned: pinned ?? this.pinned,
      pinnedAtMs: pinnedAtMs ?? this.pinnedAtMs,
      pinnedBy: pinnedBy ?? this.pinnedBy,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'leagueId': leagueId,
        'title': title,
        'message': message,
        'createdAtMs': createdAtMs,
        'authorId': authorId,
        'authorName': authorName,
        'scope': scope,
        'masterLeagueId': masterLeagueId,
        'pinned': pinned,
        'pinnedAtMs': pinnedAtMs,
        'pinnedBy': pinnedBy,
      };

  Map<String, dynamic> toJsonMap() => toMap();

  static LeagueAnnouncement fromMap(Map<String, dynamic> map) {
    return LeagueAnnouncement(
      id: (map['id'] as String? ?? '').trim(),
      leagueId: (map['leagueId'] as String? ?? '').trim(),
      title: (map['title'] as String? ?? '').trim(),
      message: (map['message'] as String? ?? '').trim(),
      createdAtMs: ((map['createdAtMs'] as num?) ?? 0).toInt(),
      authorId: (map['authorId'] as String? ?? '').trim(),
      authorName: (map['authorName'] as String? ?? '').trim(),
      scope: (map['scope'] as String? ?? 'league').trim(),
      masterLeagueId: (map['masterLeagueId'] as String? ?? '').trim(),
      pinned: map['pinned'] == true,
      pinnedAtMs: ((map['pinnedAtMs'] as num?) ?? 0).toInt(),
      pinnedBy: (map['pinnedBy'] as String? ?? '').trim(),
    );
  }

  String toJson() => jsonEncode(toMap());

  static LeagueAnnouncement fromJson(dynamic json) {
    if (json is String) {
      return fromMap(jsonDecode(json) as Map<String, dynamic>);
    }
    if (json is Map<String, dynamic>) {
      return fromMap(json);
    }
    if (json is Map) {
      return fromMap(json.cast<String, dynamic>());
    }
    throw const FormatException('Invalid LeagueAnnouncement json');
  }
}
