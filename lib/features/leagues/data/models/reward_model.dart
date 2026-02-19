import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Firestore path:
/// leagues/{leagueId}/rewards/{rewardId}
///
/// Document:
/// {
///   position: number,
///   rewardName: string,
///   rewardType: string, // cash|physical|digital|trophy|other
///   description: string,
///   imageUrl: string,
///   createdAt: timestamp,
///   createdBy: uid
/// }
class RewardModel extends Equatable {
  static const Set<String> supportedRewardTypes = <String>{
    'cash',
    'physical',
    'digital',
    'trophy',
    'other',
  };

  final String id;
  final int position;
  final String rewardName;
  final String rewardType;
  final String description;
  final String imageUrl;
  final DateTime? createdAt;
  final String createdBy;

  const RewardModel({
    required this.id,
    required this.position,
    required this.rewardName,
    required this.rewardType,
    required this.description,
    required this.imageUrl,
    required this.createdAt,
    required this.createdBy,
  });

  RewardModel copyWith({
    String? id,
    int? position,
    String? rewardName,
    String? rewardType,
    String? description,
    String? imageUrl,
    DateTime? createdAt,
    String? createdBy,
  }) {
    return RewardModel(
      id: id ?? this.id,
      position: position ?? this.position,
      rewardName: rewardName ?? this.rewardName,
      rewardType: rewardType ?? this.rewardType,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  static String normalizeRewardType(String raw) {
    final v = raw.trim().toLowerCase();
    if (supportedRewardTypes.contains(v)) return v;
    return 'other';
  }

  static RewardModel fromJson(
    Map<String, dynamic> json, {
    required String id,
  }) {
    final createdAtRaw = json['createdAt'];
    DateTime? createdAt;
    if (createdAtRaw is Timestamp) {
      createdAt = createdAtRaw.toDate();
    } else if (createdAtRaw is DateTime) {
      createdAt = createdAtRaw;
    }

    final positionRaw = json['position'];
    final position = positionRaw is num ? positionRaw.toInt() : 0;

    return RewardModel(
      id: id,
      position: position,
      rewardName: (json['rewardName'] ?? '').toString(),
      rewardType: normalizeRewardType((json['rewardType'] ?? 'other').toString()),
      description: (json['description'] ?? '').toString(),
      imageUrl: (json['imageUrl'] ?? '').toString(),
      createdAt: createdAt,
      createdBy: (json['createdBy'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'position': position,
      'rewardName': rewardName,
      'rewardType': normalizeRewardType(rewardType),
      'description': description,
      'imageUrl': imageUrl,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'createdBy': createdBy,
    };
  }

  Map<String, dynamic> toFirestoreCreateJson({
    required String createdBy,
    required FieldValue createdAt,
  }) {
    return <String, dynamic>{
      'position': position,
      'rewardName': rewardName,
      'rewardType': normalizeRewardType(rewardType),
      'description': description,
      'imageUrl': imageUrl,
      'createdAt': createdAt,
      'createdBy': createdBy,
    };
  }

  Map<String, dynamic> toFirestoreUpdateJson() {
    return <String, dynamic>{
      'position': position,
      'rewardName': rewardName,
      'rewardType': normalizeRewardType(rewardType),
      'description': description,
      'imageUrl': imageUrl,
    };
  }

  @override
  List<Object?> get props => <Object?>[
        id,
        position,
        rewardName,
        rewardType,
        description,
        imageUrl,
        createdAt,
        createdBy,
      ];
}
