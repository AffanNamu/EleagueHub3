import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String userId;
  final String teamName;
  final String authProvider;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserProfile({
    required this.userId,
    required this.teamName,
    required this.authProvider,
    required this.createdAt,
    required this.updatedAt,
  });

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
      createdAt: toDate(data['createdAt']),
      updatedAt: toDate(data['updatedAt']),
    );
  }
}
