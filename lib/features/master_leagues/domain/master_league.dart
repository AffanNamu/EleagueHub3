import 'package:cloud_firestore/cloud_firestore.dart';

class MasterLeague {
  final String id;
  final String name;
  final String ownerId;

  /// Firestore Timestamp (server time).
  final Timestamp? createdAt;

  /// Simple string status:
  /// - "active" when purchased/unlocked
  /// - can be expanded later (e.g., "trial", "refunded")
  final String purchaseStatus;

  /// Membership for read access:
  /// - owner should always be included
  final List<String> memberIds;

  const MasterLeague({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    required this.purchaseStatus,
    required this.memberIds,
  });

  bool get isActive => purchaseStatus.trim().toLowerCase() == 'active';

  Map<String, dynamic> toFirestoreMap() => <String, dynamic>{
        'name': name.trim(),
        'ownerId': ownerId.trim(),
        'createdAt': createdAt,
        'purchaseStatus': purchaseStatus.trim(),
        'memberIds': memberIds
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false),
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

    return MasterLeague(
      id: id,
      name: name,
      ownerId: ownerId,
      createdAt: createdAt,
      purchaseStatus: purchaseStatus,
      memberIds: memberIds,
    );
  }

  MasterLeague copyWith({
    String? id,
    String? name,
    String? ownerId,
    Timestamp? createdAt,
    String? purchaseStatus,
    List<String>? memberIds,
  }) {
    return MasterLeague(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      purchaseStatus: purchaseStatus ?? this.purchaseStatus,
      memberIds: memberIds ?? this.memberIds,
    );
  }
}
