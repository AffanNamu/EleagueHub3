import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Firestore path:
/// leagues/{leagueId}/rewards/{rewardId}
///
/// Document schema (enforced by Firestore security rules):
/// {
///   position    : number   (1–1000)
///   rewardName  : string   (1–120 chars)
///   rewardType  : string   cash|physical|digital|trophy|other
///   description : string   (0–6000 chars)
///   imageUrl    : string   (0–2000 chars)
///   createdAt   : timestamp  (server timestamp — set on create only)
///   createdBy   : uid string (set on create only)
///   updatedAt   : timestamp  (server timestamp — set on update only, optional)
///   updatedBy   : uid string (set on update only, optional)
/// }
///
/// IMPORTANT — Firestore write rules use hasOnly() which means sending
/// any field NOT in the allowed list causes Permission Denied.
/// The RewardFirestoreService builds write payloads explicitly and does
/// NOT call toJson() / toFirestoreCreateJson() for Firestore writes,
/// so those methods are safe for local/test use only.
class RewardModel extends Equatable {
  static const Set<String> supportedRewardTypes = <String>{
    'cash',
    'physical',
    'digital',
    'trophy',
    'other',
  };

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

  final String id;
  final int position;
  final String rewardName;
  final String rewardType;
  final String description;
  final String imageUrl;
  final DateTime? createdAt;
  final String createdBy;

  // ---------------------------------------------------------------------------
  // normalizeRewardType
  // ---------------------------------------------------------------------------
  /// Accepts nullable input for safety — returns 'other' for null/empty/unknown.
  static String normalizeRewardType(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    return supportedRewardTypes.contains(v) ? v : 'other';
  }

  // ---------------------------------------------------------------------------
  // fromJson  (used by streamRewards / fetchRewards)
  // ---------------------------------------------------------------------------
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
    final position = positionRaw is num ? positionRaw.toInt() : 1;

    return RewardModel(
      id: id,
      position: position,
      rewardName: (json['rewardName'] ?? '').toString().trim(),
      rewardType:
          normalizeRewardType((json['rewardType'] ?? 'other').toString()),
      description: (json['description'] ?? '').toString(),
      imageUrl: (json['imageUrl'] ?? '').toString().trim(),
      createdAt: createdAt,
      createdBy: (json['createdBy'] ?? '').toString(),
    );
  }

  // ---------------------------------------------------------------------------
  // toJson  (for local storage, testing, debugging — NOT for Firestore writes)
  // ---------------------------------------------------------------------------
  /// Returns a plain Dart map. Do NOT pass this directly to Firestore —
  /// use RewardFirestoreService which builds write payloads explicitly.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'position': position,
      'rewardName': rewardName.trim(),
      'rewardType': normalizeRewardType(rewardType),
      'description': description.trim(),
      'imageUrl': imageUrl.trim(),
      'createdAt':
          createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'createdBy': createdBy,
    };
  }

  // ---------------------------------------------------------------------------
  // toFirestoreCreateJson  (kept for reference / testing only)
  // ---------------------------------------------------------------------------
  /// Produces the exact map that matches the Firestore create rules hasOnly().
  /// The service calls this internally — do not add extra fields here.
  /// Fields: position, rewardName, rewardType, description, imageUrl,
  ///         createdAt (FieldValue.serverTimestamp()), createdBy (uid).
  Map<String, dynamic> toFirestoreCreateJson({
    required String createdBy,
    required FieldValue createdAt,
  }) {
    return <String, dynamic>{
      'position': position,
      'rewardName': rewardName.trim(),
      'rewardType': normalizeRewardType(rewardType),
      'description': description.trim(),
      'imageUrl': imageUrl.trim(),
      // createdAt MUST be FieldValue.serverTimestamp() — the rules check
      // request.resource.data.createdAt == request.time which is only
      // satisfied by serverTimestamp, not by DateTime.now() or Timestamp.
      'createdAt': createdAt,
      'createdBy': createdBy,
    };
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  // Equatable
  // ---------------------------------------------------------------------------
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

  @override
  String toString() {
    return 'RewardModel('
        'id: $id, '
        'position: $position, '
        'rewardName: $rewardName, '
        'rewardType: $rewardType, '
        'createdBy: $createdBy'
        ')';
  }
}
