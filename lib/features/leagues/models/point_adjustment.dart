import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore document schema (required):
/// leagues/{leagueId}/pointAdjustments/{adjustmentId}
///
/// Fields:
/// - teamId (string)
/// - type (ADDITION | DEDUCTION)
/// - points (int, positive)
/// - reason (string, required)
/// - adjustedBy (string uid)
/// - createdAt (timestamp)
enum PointAdjustmentType {
  addition,
  deduction;

  String toFirestoreString() {
    switch (this) {
      case PointAdjustmentType.addition:
        return 'ADDITION';
      case PointAdjustmentType.deduction:
        return 'DEDUCTION';
    }
  }

  static PointAdjustmentType? fromFirestoreString(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'ADDITION':
        return PointAdjustmentType.addition;
      case 'DEDUCTION':
        return PointAdjustmentType.deduction;
      default:
        return null;
    }
  }
}

class PointAdjustment {
  final String id;
  final String teamId;
  final PointAdjustmentType type;
  final int points;
  final String reason;
  final String adjustedBy;
  final DateTime createdAt;

  const PointAdjustment({
    required this.id,
    required this.teamId,
    required this.type,
    required this.points,
    required this.reason,
    required this.adjustedBy,
    required this.createdAt,
  });

  int get signedDelta => type == PointAdjustmentType.addition ? points : -points;

  static PointAdjustment fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = (doc.data() ?? <String, dynamic>{}).cast<String, dynamic>();

    final teamId = (data['teamId'] as String? ?? '').trim();
    final typeRaw = (data['type'] as String? ?? '').trim();
    final type = PointAdjustmentType.fromFirestoreString(typeRaw) ?? PointAdjustmentType.addition;

    final points = (data['points'] as num?)?.toInt() ?? 0;
    final reason = (data['reason'] as String? ?? '').trim();
    final adjustedBy = (data['adjustedBy'] as String? ?? '').trim();

    final ts = data['createdAt'];
    DateTime createdAt;
    if (ts is Timestamp) {
      createdAt = ts.toDate();
    } else {
      createdAt = DateTime.fromMillisecondsSinceEpoch(0);
    }

    return PointAdjustment(
      id: doc.id,
      teamId: teamId,
      type: type,
      points: points,
      reason: reason,
      adjustedBy: adjustedBy,
      createdAt: createdAt,
    );
  }
}
