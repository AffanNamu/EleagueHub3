import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';

class UserProfileRepository {
  UserProfileRepository({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users => _firestore.collection('users');

  Future<bool> profileExists(String userId) async {
    final doc = await _users.doc(userId).get();
    return doc.exists;
  }

  Future<UserProfile?> fetchByUserId(String userId) async {
    final doc = await _users.doc(userId).get();
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    return UserProfile.fromFirestore(userId: doc.id, data: data);
  }

  Stream<UserProfile?> watchByUserId(String userId) {
    return _users.doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      return UserProfile.fromFirestore(userId: doc.id, data: data);
    });
  }

  Future<void> createProfileIfMissing({
    required String userId,
    required String teamName,
    required String authProvider,
    Map<String, dynamic>? onboardingAnswers,
  }) async {
    final ref = _users.doc(userId);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) return;

      final payload = <String, dynamic>{
        'userId': userId,
        'teamName': teamName,
        'authProvider': authProvider,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (onboardingAnswers != null && onboardingAnswers.isNotEmpty) {
        payload['onboardingAnswers'] = onboardingAnswers;
      }

      tx.set(ref, payload);
    });
  }

  Future<void> updateTeamName({
    required String userId,
    required String teamName,
  }) async {
    await _users.doc(userId).set(
      {
        'teamName': teamName,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
