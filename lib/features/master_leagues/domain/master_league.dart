import 'package:cloud_firestore/cloud_firestore.dart';

import 'master_league_plan.dart';

class MasterLeague {
  final String id;
  final String name;
  final String ownerId;

  /// Firestore Timestamp (server time).
  final Timestamp? createdAt;

  /// Simple string status:
  /// - "active" when purchased/unlocked
  final String purchaseStatus;

  /// Membership for read access:
  /// - owner should always be included
  final List<String> memberIds;

  /// The plan tier for this master league.
  final MasterLeaguePlan plan;

  const MasterLeague({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    required this.purchaseStatus,
    required this.memberIds,
    this.plan = MasterLeaguePlan.basic,
  });

  bool get isActive => purchaseStatus.trim().toLowerCase() == 'active';

  int get maxLeagues => plan.maxLeagues;
  int get maxTeamsPerLeague => plan.maxTeamsPerLeague;

  Map<String, dynamic> toFirestoreMap() => <String, dynamic>{
        'name': name.trim(),
        'ownerId': ownerId.trim(),
        'createdAt': createdAt,
        'purchaseStatus': purchaseStatus.trim(),
        'memberIds': memberIds
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false),
        'plan': plan.id,
      };

  static MasterLeague fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = (doc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    return fromMap(doc.id, data);
  }

  static MasterLeague fromMap(String id, Map<String, dynamic> map) {
    final name = (map['name'] as String?) ?? '';
    final ownerId =
        (map['ownerId'] as String?) ?? (map['ownerUid'] as String?) ?? '';
    final createdAt =
        map['createdAt'] is Timestamp ? map['createdAt'] as Timestamp : null;
    final purchaseStatus = (map['purchaseStatus'] as String?) ?? 'active';

    final memberIdsRaw = map['memberIds'];
    final memberIds = (memberIdsRaw is List)
        ? memberIdsRaw
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    final plan = MasterLeaguePlan.fromString(map['plan'] as String?);

    return MasterLeague(
      id: id,
      name: name,
      ownerId: ownerId,
      createdAt: createdAt,
      purchaseStatus: purchaseStatus,
      memberIds: memberIds,
      plan: plan,
    );
  }

  MasterLeague copyWith({
    String? id,
    String? name,
    String? ownerId,
    Timestamp? createdAt,
    String? purchaseStatus,
    List<String>? memberIds,
    MasterLeaguePlan? plan,
  }) {
    return MasterLeague(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      purchaseStatus: purchaseStatus ?? this.purchaseStatus,
      memberIds: memberIds ?? this.memberIds,
      plan: plan ?? this.plan,
    );
  }
}
