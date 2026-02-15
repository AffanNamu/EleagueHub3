class Team {
  final String id;
  final String leagueId;
  final String name;

  /// Team image/logo URL (Cloudinary secure_url recommended).
  /// Empty string means "no image" -> UI should show existing placeholder.
  final String teamImageUrl;

  /// For UCL Group: the group name/id this team belongs to (e.g. "Group A").
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
    this.teamImageUrl = '',
  });

  Map<String, dynamic> toJson() => toRemoteMap();
  factory Team.fromJson(Map<String, dynamic> json) => fromRemoteMap(json);

  Map<String, dynamic> toRemoteMap() => {
        'id': id,
        'leagueId': leagueId,
        'name': name,
        'teamImageUrl': teamImageUrl,
        'groupId': groupId,
        'updatedAtMs': updatedAtMs,
        'version': version,
      };

  static Team fromRemoteMap(Map<String, dynamic> map) {
    final id = (map['id'] as String?) ?? '';
    final leagueId = (map['leagueId'] as String?) ?? '';
    final name = (map['name'] as String?) ?? '';

    // Backward/forward-compatible image keys (prefer teamImageUrl).
    final teamImageUrl = (map['teamImageUrl'] as String?)?.trim().isNotEmpty == true
        ? (map['teamImageUrl'] as String).trim()
        : ((map['logoUrl'] as String?)?.trim().isNotEmpty == true
            ? (map['logoUrl'] as String).trim()
            : ((map['imageUrl'] as String?)?.trim().isNotEmpty == true ? (map['imageUrl'] as String).trim() : ''));

    return Team(
      id: id,
      leagueId: leagueId,
      name: name,
      groupId: map['groupId'] as String?, // old data has no key -> null
      teamImageUrl: teamImageUrl,
      updatedAtMs: (map['updatedAtMs'] as num).toInt(),
      version: (map['version'] as num).toInt(),
    );
  }

  Team copyWith({
    String? id,
    String? leagueId,
    String? name,
    String? groupId,
    String? teamImageUrl,
    int? updatedAtMs,
    int? version,
  }) {
    return Team(
      id: id ?? this.id,
      leagueId: leagueId ?? this.leagueId,
      name: name ?? this.name,
      groupId: groupId ?? this.groupId,
      teamImageUrl: teamImageUrl ?? this.teamImageUrl,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      version: version ?? this.version,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Team && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
