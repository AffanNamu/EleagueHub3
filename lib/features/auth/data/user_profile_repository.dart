import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';

class UserProfileRepositoryException implements Exception {
  final String message;
  const UserProfileRepositoryException(this.message);

  @override
  String toString() => message;
}

class UserProfileRepository {
  UserProfileRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _usersCol =>
      _firestore.collection('users');

  String _requireAuthUid() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const UserProfileRepositoryException(
        'Please sign in and try again.',
      );
    }
    return uid;
  }

  Never _rethrowFriendly(Object error) {
    if (error is UserProfileRepositoryException) throw error;

    if (error is SocketException) {
      throw const UserProfileRepositoryException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    }

    if (error is TimeoutException) {
      throw const UserProfileRepositoryException(
        'Your internet connection seems unstable. Please try again.',
      );
    }

    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          throw const UserProfileRepositoryException(
            'You do not have permission to access this profile.',
          );
        case 'unauthenticated':
          throw const UserProfileRepositoryException(
            'Please sign in and try again.',
          );
        case 'unavailable':
        case 'deadline-exceeded':
          throw const UserProfileRepositoryException(
            'Your network appears to be offline. Please check your connection and try again.',
          );
        default:
          throw const UserProfileRepositoryException(
            "We couldn't complete this profile request. Please try again.",
          );
      }
    }

    throw const UserProfileRepositoryException(
      'Something went wrong. Please try again.',
    );
  }

  Future<UserProfile?> fetchByUserId(String userId) async {
    try {
      _requireAuthUid();

      final uid = userId.trim();
      if (uid.isEmpty) return null;

      final snap = await _usersCol
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      if (!snap.exists) return null;
      return UserProfile.fromDoc(snap);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Stream<UserProfile?> watchByUserId(String userId) {
    try {
      _requireAuthUid();

      final uid = userId.trim();
      if (uid.isEmpty) return const Stream<UserProfile?>.value(null);

      return _usersCol.doc(uid).snapshots().map((snap) {
        if (!snap.exists) return null;
        return UserProfile.fromDoc(snap);
      });
    } catch (_) {
      return const Stream<UserProfile?>.empty();
    }
  }

  Future<UserProfile?> fetchByShareId(String shareId) async {
    try {
      _requireAuthUid();

      final normalized = shareId.trim();
      if (normalized.isEmpty) return null;

      final snap = await _usersCol
          .where('shareId', isEqualTo: normalized)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      if (snap.docs.isEmpty) return null;
      return UserProfile.fromDoc(snap.docs.first);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<Map<String, UserProfile>> fetchByUserIds(List<String> userIds) async {
    try {
      _requireAuthUid();

      final ids = userIds
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);

      if (ids.isEmpty) return const <String, UserProfile>{};

      final out = <String, UserProfile>{};

      const int chunkSize = 10;
      for (int i = 0; i < ids.length; i += chunkSize) {
        final end = (i + chunkSize < ids.length) ? i + chunkSize : ids.length;
        final chunk = ids.sublist(i, end);

        final snap = await _usersCol
            .where(FieldPath.documentId, whereIn: chunk)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 15));

        for (final doc in snap.docs) {
          final profile = UserProfile.fromDoc(doc);
          out[profile.userId] = profile;
        }
      }

      return out;
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> saveOrUpdateSelf(UserProfile profile) async {
    try {
      final authUid = _requireAuthUid();
      if (profile.userId.trim() != authUid) {
        throw const UserProfileRepositoryException(
          'You can only update your own profile.',
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final payload = <String, dynamic>{
        ...profile.toJson(),
        'userId': authUid,
        'updatedAt': now,
      };

      if (payload['createdAt'] == null || payload['createdAt'] == 0) {
        payload['createdAt'] = now;
      }

      await _usersCol
          .doc(authUid)
          .set(payload, SetOptions(merge: true))
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> updateTeamName(String teamName) async {
    try {
      final authUid = _requireAuthUid();
      final value = teamName.trim();
      if (value.isEmpty) {
        throw const UserProfileRepositoryException(
          'Please enter a team name.',
        );
      }

      await _usersCol.doc(authUid).set(
        <String, dynamic>{
          'userId': authUid,
          'teamName': value,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> ensureShareIdIfMissing() async {
    try {
      final authUid = _requireAuthUid();
      final doc = await _usersCol
          .doc(authUid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      final data = doc.data() ?? <String, dynamic>{};
      final current = (data['shareId'] as String? ?? '').trim();
      if (current.isNotEmpty) return;

      final derived = UserProfile.deriveShareIdFromUid(authUid).trim();
      if (derived.isEmpty) return;

      await _usersCol.doc(authUid).set(
        <String, dynamic>{
          'userId': authUid,
          'shareId': derived,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> updateQuickMessages(List<String> quickMessages) async {
    try {
      final authUid = _requireAuthUid();
      final values = quickMessages
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .take(15)
          .toList(growable: false);

      await _usersCol.doc(authUid).set(
        <String, dynamic>{
          'userId': authUid,
          'quickMessagesCustom': values,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> updateProfileImages({
    String? photoUrl,
    String? profileImageUrl,
    String? teamImageUrl,
  }) async {
    try {
      final authUid = _requireAuthUid();
      final payload = <String, dynamic>{
        'userId': authUid,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

      if (photoUrl != null) payload['photoUrl'] = photoUrl.trim();
      if (profileImageUrl != null) {
        payload['profileImageUrl'] = profileImageUrl.trim();
      }
      if (teamImageUrl != null) payload['teamImageUrl'] = teamImageUrl.trim();

      await _usersCol
          .doc(authUid)
          .set(payload, SetOptions(merge: true))
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> createIfMissing({
    required String authProvider,
    required String teamName,
  }) async {
    try {
      final authUid = _requireAuthUid();
      final ref = _usersCol.doc(authUid);
      final existing = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      if (existing.exists) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      await ref.set(
        <String, dynamic>{
          'userId': authUid,
          'teamName': teamName.trim(),
          'authProvider': authProvider.trim(),
          'createdAt': now,
          'updatedAt': now,
          'shareId': UserProfile.deriveShareIdFromUid(authUid),
        },
        SetOptions(merge: false),
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> refreshShareIdFromUidIfEmpty() async {
    await ensureShareIdIfMissing();
  }

  Future<void> debugEnsureSelfProfile() async {
    if (!kDebugMode) return;
    try {
      await ensureShareIdIfMissing();
    } catch (_) {}
  }
}
