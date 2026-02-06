import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  /// Immutable internal id (Firebase Auth uid). Also the Firestore doc id.
  final String userId;

  /// Editable by user later.
  final String teamName;

  /// 'google.com' | 'password' | ...
  final String authProvider;

  /// Short user-facing share id (e.g. eS44e35f). Used for admin/player sharing.
  ///
  /// IMPORTANT: This is NOT the internal userId. Internal userId remains Firebase uid.
  final String? shareId;

  /// Premium entitlement (stored in Firestore user doc).
  ///
  /// Field name: isPremium: bool
  final bool isPremium;

  /// Premium-only: user-created quick messages (stored in Firestore user doc).
  ///
  /// Field name: quickMessagesCustom: List<String>
  final List<String> quickMessagesCustom;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserProfile({
    required this.userId,
    required this.teamName,
    required this.authProvider,
    required this.shareId,
    required this.isPremium,
    required this.quickMessagesCustom,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Fallback for display only (in case shareId hasn't been stored yet).
  static String deriveShareIdFromUid(String uid) {
    final compact = uid.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final core = (compact.length >= 6) ? compact.substring(0, 6) : compact.padRight(6, '0');
    return 'eS$core';
  }

  /// Prefer the stored shareId. If missing, derive one for display.
  String get effectiveShareId {
    final v = shareId?.trim();
    if (v != null && v.isNotEmpty) return v;
    return deriveShareIdFromUid(userId);
  }

  static List<String> _stringList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => (e ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  static UserProfile fromFirestore({
    required String userId,
    required Map<String, dynamic> data,
  }) {
    DateTime? toDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return UserProfile(
      userId: (data['userId'] as String?) ?? userId,
      teamName: (data['teamName'] as String?) ?? '',
      authProvider: (data['authProvider'] as String?) ?? 'unknown',
      shareId: (data['shareId'] as String?)?.trim(),
      isPremium: data['isPremium'] == true,
      quickMessagesCustom: _stringList(data['quickMessagesCustom']),
      createdAt: toDate(data['createdAt']),
      updatedAt: toDate(data['updatedAt']),
    );
  }
}
