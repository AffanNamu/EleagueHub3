//team.dart
class Team {
  // Participant type: whether this team already has a live eSportlyic
  // account behind it, or was created directly by the organizer and is
  // awaiting a real owner to claim it. Absent on every pre-existing team
  // doc -- fromRemoteMap defaults that to [participantTypeRegistered], so
  // no migration is required and no existing team's behavior changes.
  static const String participantTypeRegistered = 'registered';
  static const String participantTypeExternal = 'external';

  // Claim lifecycle for an external team. Only meaningful when
  // participantType == external; null/absent for every registered team
  // (claiming isn't a concept that applies to them).
  static const String claimStatusNotClaimed = 'not_claimed';
  static const String claimStatusPending = 'claim_pending';
  static const String claimStatusClaimed = 'claimed';
  static const String claimStatusRevoked = 'revoked';
  static const String claimStatusExpired = 'expired';

  final String id;
  final String leagueId;
  final String name;

  /// Rules-authoritative owner uid for this team.
  ///
  /// In this app's current data model, teams are usually UID-based (Team.id == user uid),
  /// so ownerId is typically the same as id. Kept explicit for security rules + future-proofing.
  ///
  /// For an external team, this is empty until claimed (toRemoteMap's existing
  /// fallback-to-id behavior still applies, so it reads as the team's own doc
  /// ID, not a real account -- never treat a non-empty ownerId alone as proof
  /// of a live account; check participantType/claimStatus instead).
  final String ownerId;

  /// 'registered' (default, matches every existing team) or 'external'
  /// (organizer-created, no eSportlyic account yet -- see claimStatus).
  final String participantType;

  /// Claim lifecycle state for an external team (null for registered teams).
  final String? claimStatus;

  /// When the team was claimed (epoch ms), if ever.
  final int? claimedAtMs;

  /// Organizer uid who created this team doc. Null for teams created via
  /// the original "add an existing eSportlyic user" flow (not tracked
  /// historically); set for every manually-created external team.
  final String? createdByUserId;

  /// Team image/logo URL (Cloudinary secure_url recommended).
  /// Empty string means "no image" -> UI should show existing placeholder.
  final String teamImageUrl;

  /// For UCL Group: the group name/id this team belongs to (e.g. "Group A").
  /// For classic and Swiss formats: usually null.
  final String? groupId;

  /// Points derived from match results only (no admin adjustments).
  /// Required Firestore schema field: basePoints
  final int basePoints;

  /// Net admin adjustments (can be negative).
  /// Required Firestore schema field: adminAdjustment
  final int adminAdjustment;

  /// Final points used for ordering standings: basePoints + adminAdjustment
  /// Required Firestore schema field: finalPoints
  final int finalPoints;

  /// Cached goal difference for scalable ordering/queries.
  /// Required Firestore schema field: goalDifference
  final int goalDifference;

  /// Cached goals for for scalable ordering/queries.
  /// Required Firestore schema field: goalsFor
  final int goalsFor;

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
    this.ownerId = '',
    this.basePoints = 0,
    this.adminAdjustment = 0,
    this.finalPoints = 0,
    this.goalDifference = 0,
    this.goalsFor = 0,
    this.participantType = participantTypeRegistered,
    this.claimStatus,
    this.claimedAtMs,
    this.createdByUserId,
  });

  bool get isExternal => participantType == participantTypeExternal;
  bool get isClaimed => !isExternal || claimStatus == claimStatusClaimed;

  Map<String, dynamic> toJson() => toRemoteMap();
  factory Team.fromJson(Map<String, dynamic> json) => fromRemoteMap(json);

  Map<String, dynamic> toRemoteMap() => {
        'id': id,
        'leagueId': leagueId,
        'name': name,

        // Ownership (required by updated security rules; backward compatible)
        'ownerId': ownerId.trim().isNotEmpty ? ownerId.trim() : id,

        'teamImageUrl': teamImageUrl,
        'groupId': groupId,

        // Required points schema fields (safe defaults).
        // SECURITY NOTE:
        // - Firestore rules should enforce finalPoints == basePoints + adminAdjustment.
        // - Client must keep this invariant on any write that touches these fields.
        'basePoints': basePoints,
        'adminAdjustment': adminAdjustment,
        'finalPoints': finalPoints == (basePoints + adminAdjustment) ? finalPoints : (basePoints + adminAdjustment),
        'goalDifference': goalDifference,
        'goalsFor': goalsFor,

        'participantType': participantType,
        if (claimStatus != null) 'claimStatus': claimStatus,
        if (claimedAtMs != null) 'claimedAtMs': claimedAtMs,
        if (createdByUserId != null) 'createdByUserId': createdByUserId,

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

    final ownerIdRaw = (map['ownerId'] as String?)?.trim() ?? '';
    final ownerId = ownerIdRaw.isNotEmpty ? ownerIdRaw : id;

    final basePoints = (map['basePoints'] as num?)?.toInt() ?? 0;
    final adminAdjustment = (map['adminAdjustment'] as num?)?.toInt() ?? 0;

    // If finalPoints isn't present (older docs), compute it.
    final computedFinal = basePoints + adminAdjustment;
    final finalPoints = (map['finalPoints'] as num?)?.toInt() ?? computedFinal;

    final goalDifference = (map['goalDifference'] as num?)?.toInt() ?? 0;
    final goalsFor = (map['goalsFor'] as num?)?.toInt() ?? 0;

    return Team(
      id: id,
      leagueId: leagueId,
      name: name,
      ownerId: ownerId,
      groupId: map['groupId'] as String?, // old data has no key -> null
      teamImageUrl: teamImageUrl,
      basePoints: basePoints,
      adminAdjustment: adminAdjustment,
      finalPoints: finalPoints,
      goalDifference: goalDifference,
      goalsFor: goalsFor,
      participantType: (map['participantType'] as String?)?.trim().isNotEmpty == true
          ? (map['participantType'] as String).trim()
          : participantTypeRegistered,
      claimStatus: (map['claimStatus'] as String?)?.trim().isNotEmpty == true
          ? (map['claimStatus'] as String).trim()
          : null,
      claimedAtMs: (map['claimedAtMs'] as num?)?.toInt(),
      createdByUserId: (map['createdByUserId'] as String?)?.trim().isNotEmpty == true
          ? (map['createdByUserId'] as String).trim()
          : null,
      updatedAtMs: (map['updatedAtMs'] as num?)?.toInt() ?? 0,
      version: (map['version'] as num?)?.toInt() ?? 1,
    );
  }

  Team copyWith({
    String? id,
    String? leagueId,
    String? name,
    String? groupId,
    String? teamImageUrl,
    String? ownerId,
    int? basePoints,
    int? adminAdjustment,
    int? finalPoints,
    int? goalDifference,
    int? goalsFor,
    String? participantType,
    String? claimStatus,
    int? claimedAtMs,
    String? createdByUserId,
    int? updatedAtMs,
    int? version,
  }) {
    final nextBase = basePoints ?? this.basePoints;
    final nextAdj = adminAdjustment ?? this.adminAdjustment;
    final nextFinal = finalPoints ?? (nextBase + nextAdj);

    return Team(
      id: id ?? this.id,
      leagueId: leagueId ?? this.leagueId,
      name: name ?? this.name,
      groupId: groupId ?? this.groupId,
      teamImageUrl: teamImageUrl ?? this.teamImageUrl,
      ownerId: ownerId ?? this.ownerId,
      basePoints: nextBase,
      adminAdjustment: nextAdj,
      finalPoints: nextFinal,
      goalDifference: goalDifference ?? this.goalDifference,
      goalsFor: goalsFor ?? this.goalsFor,
      participantType: participantType ?? this.participantType,
      claimStatus: claimStatus ?? this.claimStatus,
      claimedAtMs: claimedAtMs ?? this.claimedAtMs,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      version: version ?? this.version,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Team && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
