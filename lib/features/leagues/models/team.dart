class Team {
  final String id;
  final String leagueId;
  final String name;

  /// For UCL Group: the group name this team belongs to (e.g. "Group A").
  /// For classic and Swiss formats: usually null.
  final String? groupId;

  final int updatedAtMs;
  final int version;

  const Team({
    required this.id,
    required this.leagueId,
    required this.name,
    required this.updatedAtMs,
    required this.version,
    this.groupId,
  });

  Map<String, dynamic> toJson() => toRemoteMap();
  factory Team.fromJson(Map<String, dynamic> json) =>
      fromRemoteMap(json);

  Map<String, dynamic> toRemoteMap() => {
        'id': id,
        'leagueId': leagueId,
        'name': name,
        'groupId': groupId,
        'updatedAtMs': updatedAtMs,
        'version': version,
      };

  static Team fromRemoteMap(Map<String, dynamic> map) {
    return Team(
      id: map['id'] as String,
      leagueId: map['leagueId'] as String,
      name: map['name'] as String,
      groupId: map['groupId'] as String?, // old data has no key -> null
      updatedAtMs: (map['updatedAtMs'] as num).toInt(),
      version: (map['version'] as num).toInt(),
    );
  }

  Team copyWith({
    String? id,
    String? leagueId,
    String? name,
    String? groupId,
    int? updatedAtMs,
    int? version,
  }) {
    return Team(
      id: id ?? this.id,
      leagueId: leagueId ?? this.leagueId,
      name: name ?? this.name,
      groupId: groupId ?? this.groupId,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      version: version ?? this.version,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Team &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
