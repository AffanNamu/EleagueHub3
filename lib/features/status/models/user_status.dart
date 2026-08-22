// lib/features/status/models/user_status.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// A temporary profile status/story update (Feature 2 — Status System).
/// Lives at users/{uid}/statuses/{statusId}.
///
/// This is a Status/Story-style temporary update — NOT a Reels/TikTok
/// video feed. Media is a single image plus an optional short caption.
class UserStatus {
  const UserStatus({
    required this.statusId,
    required this.userId,
    required this.imageUrl,
    required this.caption,
    required this.createdAtMs,
    required this.expiresAtMs,
  });

  final String statusId;
  final String userId;
  final String imageUrl;
  final String caption;
  final int createdAtMs;
  final int expiresAtMs;

  /// Standard status lifetime — kept in one place so the client-side
  /// expiry window matches what the Firestore rule allows.
  static const Duration lifetime = Duration(hours: 24);

  bool get isExpired => expiresAtMs <= DateTime.now().millisecondsSinceEpoch;
  bool get isActive => !isExpired;

  factory UserStatus.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    return UserStatus(
      statusId: doc.id,
      userId: (map['userId'] as String? ?? '').trim(),
      imageUrl: (map['imageUrl'] as String? ?? '').trim(),
      caption: (map['caption'] as String? ?? '').trim(),
      createdAtMs: _asInt(map['createdAtMs']),
      expiresAtMs: _asInt(map['expiresAtMs']),
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}
