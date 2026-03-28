class OrganizerFeedEvent {
  final String id;
  final String masterLeagueId;
  final String type;
  final String title;
  final String message;
  final int createdAtMs;
  final String actorId;
  final String actorName;
  final String leagueId;

  const OrganizerFeedEvent({
    required this.id,
    required this.masterLeagueId,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAtMs,
    required this.actorId,
    required this.actorName,
    required this.leagueId,
  });

  /// Firestore security rules expect these exact keys:
  ///   'id', 'masterLeagueId', 'type', 'title', 'message',
  ///   'createdAtMs', 'actorId', 'actorName', 'leagueId'
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id.trim(),
      'masterLeagueId': masterLeagueId.trim(),
      'type': type.trim(),
      'title': title.trim(),
      'message': message.trim(),
      'createdAtMs': createdAtMs,
      'actorId': actorId.trim(),
      'actorName': actorName.trim(),
      'leagueId': leagueId.trim(),
    };
  }

  factory OrganizerFeedEvent.fromMap(Map<String, dynamic> map) {
    return OrganizerFeedEvent(
      id: (map['id'] as String? ?? map['feedId'] as String? ?? '').trim(),
      masterLeagueId: (map['masterLeagueId'] as String? ?? '').trim(),
      type: (map['type'] as String? ?? '').trim(),
      title: (map['title'] as String? ?? '').trim(),
      message: (map['message'] as String? ?? '').trim(),
      createdAtMs: ((map['createdAtMs'] as num?) ?? 0).toInt(),
      actorId: (map['actorId'] as String? ?? '').trim(),
      actorName: (map['actorName'] as String? ?? '').trim(),
      leagueId: (map['leagueId'] as String? ?? '').trim(),
    );
  }

  OrganizerFeedEvent copyWith({
    String? id,
    String? masterLeagueId,
    String? type,
    String? title,
    String? message,
    int? createdAtMs,
    String? actorId,
    String? actorName,
    String? leagueId,
  }) {
    return OrganizerFeedEvent(
      id: id ?? this.id,
      masterLeagueId: masterLeagueId ?? this.masterLeagueId,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      actorId: actorId ?? this.actorId,
      actorName: actorName ?? this.actorName,
      leagueId: leagueId ?? this.leagueId,
    );
  }
}
