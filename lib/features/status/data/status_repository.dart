// lib/features/status/data/status_repository.dart
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_status.dart';

class StatusRepositoryException implements Exception {
  final String message;
  const StatusRepositoryException(this.message);

  @override
  String toString() => message;
}

/// Data layer for Feature 2 — the temporary Status system.
/// Firestore path: users/{uid}/statuses/{statusId}
class StatusRepository {
  StatusRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _statusesCol(String userId) =>
      _firestore.collection('users').doc(userId).collection('statuses');

  String _requireAuthUid() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const StatusRepositoryException('Please sign in and try again.');
    }
    return uid;
  }

  Never _rethrowFriendly(Object e) {
    if (e is StatusRepositoryException) throw e;
    if (e is SocketException) {
      throw const StatusRepositoryException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    }
    if (e is TimeoutException) {
      throw const StatusRepositoryException(
        'Your internet connection seems unstable. Please try again.',
      );
    }
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          throw const StatusRepositoryException(
            'You do not have permission to do that. A Pro or Elite plan is required to post a status.',
          );
        case 'unavailable':
        case 'deadline-exceeded':
          throw const StatusRepositoryException(
            'Your network appears to be offline. Please check your connection and try again.',
          );
        default:
          throw const StatusRepositoryException(
            "We couldn't complete this action. Please try again.",
          );
      }
    }
    throw const StatusRepositoryException('Something went wrong. Please try again.');
  }

  /// Creates a new status for the currently signed-in user. The
  /// document ID is generated client-side via `.doc()` so it can be
  /// embedded as `statusId` in the same write the Firestore rule
  /// checks against (`request.resource.data.statusId == statusId`).
  Future<void> createStatus({required String imageUrl, String caption = ''}) async {
    try {
      final authUid = _requireAuthUid();
      final url = imageUrl.trim();
      if (url.isEmpty) {
        throw const StatusRepositoryException('Please select an image for your status.');
      }

      final ref = _statusesCol(authUid).doc();
      final now = DateTime.now().millisecondsSinceEpoch;
      final expires = now + UserStatus.lifetime.inMilliseconds;
      final trimmedCaption = caption.trim();

      await ref.set(<String, dynamic>{
        'statusId': ref.id,
        'userId': authUid,
        'imageUrl': url,
        'caption': trimmedCaption.length > 200
            ? trimmedCaption.substring(0, 200)
            : trimmedCaption,
        'createdAtMs': now,
        'expiresAtMs': expires,
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// True if [userId] currently has at least one non-expired status.
  /// Used to render the status ring around a profile avatar.
  Stream<bool> watchHasActiveStatus(String userId) {
    final uid = userId.trim();
    if (uid.isEmpty) return Stream<bool>.value(false);

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return _statusesCol(uid)
        .where('expiresAtMs', isGreaterThan: nowMs)
        .snapshots()
        .map((snap) => snap.docs.isNotEmpty)
        .handleError((_) {});
  }

  /// One-time fetch of every currently-active status for [userId],
  /// oldest first, for the status viewer.
  Future<List<UserStatus>> fetchActiveStatuses(String userId) async {
    try {
      final uid = userId.trim();
      if (uid.isEmpty) return const <UserStatus>[];

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final snap = await _statusesCol(uid)
          .where('expiresAtMs', isGreaterThan: nowMs)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      final items = snap.docs.map(UserStatus.fromDoc).toList();
      items.sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
      return items;
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Deletes a status. Only the owner may do this (enforced both here
  /// via the auth-uid match, and server-side by the Firestore rule).
  Future<void> deleteStatus({required String userId, required String statusId}) async {
    try {
      final authUid = _requireAuthUid();
      if (userId.trim() != authUid) {
        throw const StatusRepositoryException('You can only delete your own status.');
      }
      await _statusesCol(authUid)
          .doc(statusId)
          .delete()
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }
}
