import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';

class UserProfileRepository {
  UserProfileRepository({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users => _firestore.collection('users');

  static bool _looksLikeShareId(String raw) {
    final s = raw.trim();
    // Example: eS44e35f (prefix eS + 4..12 alnum)
    return RegExp(r'^eS[A-Za-z0-9]{4,12}$').hasMatch(s);
  }

  static String _generateShareId(String userId) {
    // Deterministic, starts with eS, short for human sharing.
    return UserProfile.deriveShareIdFromUid(userId);
  }

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

  Future<UserProfile?> fetchByShareId(String shareId) async {
    final sid = shareId.trim();
    if (sid.isEmpty) return null;

    final snap = await _users.where('shareId', isEqualTo: sid).limit(1).get();
    if (snap.docs.isEmpty) return null;

    final doc = snap.docs.first;
    final data = doc.data();
    return UserProfile.fromFirestore(userId: doc.id, data: data);
  }

  /// Accepts either:
  /// - Firebase uid (internal userId), or
  /// - short Share ID (e.g. eS44e35f)
  Future<UserProfile?> fetchByUserIdOrShareId(String userIdOrShareId) async {
    final key = userIdOrShareId.trim();
    if (key.isEmpty) return null;

    if (_looksLikeShareId(key)) {
      return fetchByShareId(key);
    }
    return fetchByUserId(key);
  }

  /// Resolves a shareId (eS...) to the real Firebase uid (doc id).
  Future<String?> resolveUserIdFromShareId(String shareId) async {
    final sid = shareId.trim();
    if (sid.isEmpty) return null;

    final snap = await _users.where('shareId', isEqualTo: sid).limit(1).get();
    if (snap.docs.isEmpty) return null;

    return snap.docs.first.id;
  }

  Stream<UserProfile?> watchByUserId(String userId) {
    return _users.doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      return UserProfile.fromFirestore(userId: doc.id, data: data);
    });
  }

  Stream<bool> watchIsPremium(String userId) {
    return _users.doc(userId).snapshots().map((doc) {
      if (!doc.exists) return false;
      final data = doc.data();
      if (data == null) return false;
      return data['isPremium'] == true;
    });
  }

  Stream<List<String>> watchQuickMessagesCustom(String userId) {
    return _users.doc(userId).snapshots().map((doc) {
      if (!doc.exists) return const <String>[];
      final data = doc.data();
      if (data == null) return const <String>[];

      final raw = data['quickMessagesCustom'];
      if (raw is! List) return const <String>[];

      return raw
          .map((e) => (e ?? '').toString().trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    });
  }

  Future<void> updateQuickMessagesCustom({
    required String userId,
    required List<String> messages,
  }) async {
    final cleaned = messages.map((e) => e.trim()).where((s) => s.isNotEmpty).toList(growable: false);

    await _users.doc(userId).set(
      {
        'quickMessagesCustom': cleaned,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> setPremium({
    required String userId,
    required bool isPremium,
  }) async {
    await _users.doc(userId).set(
      {
        'isPremium': isPremium,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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
        'shareId': _generateShareId(userId),

        // Defaults for new users
        'isPremium': false,
        'quickMessagesCustom': <String>[],

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
