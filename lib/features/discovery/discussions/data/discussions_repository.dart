import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/discussion_reply.dart';
import '../models/discussion_thread.dart';

class DiscussionsRepositoryException implements Exception {
  final String message;
  const DiscussionsRepositoryException(this.message);

  @override
  String toString() => message;
}

/// Data layer for the Community "Discussions" pillar.
/// Firestore paths:
///   discussion_threads/{threadId}
///   discussion_threads/{threadId}/replies/{replyId}
class DiscussionsRepository {
  DiscussionsRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _threadsCol =>
      _firestore.collection('discussion_threads');

  CollectionReference<Map<String, dynamic>> _repliesCol(String threadId) =>
      _threadsCol.doc(threadId).collection('replies');

  String _requireAuthUid() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const DiscussionsRepositoryException('Please sign in and try again.');
    }
    return uid;
  }

  Never _rethrowFriendly(Object e) {
    if (e is DiscussionsRepositoryException) throw e;
    if (e is SocketException) {
      throw const DiscussionsRepositoryException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    }
    if (e is TimeoutException) {
      throw const DiscussionsRepositoryException(
        'Your internet connection seems unstable. Please try again.',
      );
    }
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          throw const DiscussionsRepositoryException(
            'You do not have permission to do that.',
          );
        case 'unavailable':
        case 'deadline-exceeded':
          throw const DiscussionsRepositoryException(
            'Your network appears to be offline. Please check your connection and try again.',
          );
        default:
          throw const DiscussionsRepositoryException(
            "We couldn't complete this action. Please try again.",
          );
      }
    }
    throw const DiscussionsRepositoryException('Something went wrong. Please try again.');
  }

  /// Creates a new discussion thread. Open to any signed-in user —
  /// Discussions is a community-engagement pillar, not a Pro/Elite
  /// promotional surface (unlike Status/Public Feed posting).
  Future<void> createThread({
    required String authorDisplayName,
    required String authorPhotoUrl,
    required String title,
    required String body,
  }) async {
    try {
      final authUid = _requireAuthUid();
      final trimmedTitle = title.trim();
      final trimmedBody = body.trim();
      if (trimmedTitle.isEmpty) {
        throw const DiscussionsRepositoryException('Please add a title.');
      }

      final ref = _threadsCol.doc();
      final now = DateTime.now().millisecondsSinceEpoch;

      await ref.set(<String, dynamic>{
        'threadId': ref.id,
        'authorId': authUid,
        'authorDisplayName': authorDisplayName.trim(),
        'authorPhotoUrl': authorPhotoUrl.trim(),
        'title': trimmedTitle.length > 140 ? trimmedTitle.substring(0, 140) : trimmedTitle,
        'body': trimmedBody.length > 4000 ? trimmedBody.substring(0, 4000) : trimmedBody,
        'createdAtMs': now,
        'lastReplyAtMs': now,
        'replyCount': 0,
        'deleted': false,
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Stream<List<DiscussionThread>> watchThreads({int limit = 40}) {
    return _threadsCol
        .where('deleted', isEqualTo: false)
        .orderBy('lastReplyAtMs', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(DiscussionThread.fromDoc).toList(growable: false))
        .handleError((_) {});
  }

  Stream<DiscussionThread?> watchThread(String threadId) {
    return _threadsCol.doc(threadId).snapshots().map(
          (doc) => doc.exists ? DiscussionThread.fromDoc(doc) : null,
        );
  }

  Stream<List<DiscussionReply>> watchReplies(String threadId, {int limit = 200}) {
    return _repliesCol(threadId)
        .where('deleted', isEqualTo: false)
        .orderBy('createdAtMs', descending: false)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(DiscussionReply.fromDoc).toList(growable: false))
        .handleError((_) {});
  }

  /// Adds a reply and increments the parent thread's replyCount /
  /// lastReplyAtMs in the same transaction, so the thread list's
  /// ordering and count stay consistent with actual reply writes.
  Future<void> createReply({
    required String threadId,
    required String authorDisplayName,
    required String authorPhotoUrl,
    required String text,
  }) async {
    try {
      final authUid = _requireAuthUid();
      final trimmedText = text.trim();
      if (trimmedText.isEmpty) {
        throw const DiscussionsRepositoryException('Please enter a reply.');
      }

      final threadRef = _threadsCol.doc(threadId);
      final replyRef = _repliesCol(threadId).doc();
      final now = DateTime.now().millisecondsSinceEpoch;

      await _firestore.runTransaction((txn) async {
        final threadSnap = await txn.get(threadRef);
        if (!threadSnap.exists) {
          throw const DiscussionsRepositoryException('This discussion no longer exists.');
        }
        final currentCount = ((threadSnap.data() ?? {})['replyCount'] as num?)?.toInt() ?? 0;

        txn.set(replyRef, <String, dynamic>{
          'replyId': replyRef.id,
          'threadId': threadId,
          'authorId': authUid,
          'authorDisplayName': authorDisplayName.trim(),
          'authorPhotoUrl': authorPhotoUrl.trim(),
          'text': trimmedText.length > 2000 ? trimmedText.substring(0, 2000) : trimmedText,
          'createdAtMs': now,
          'deleted': false,
        });

        txn.update(threadRef, <String, dynamic>{
          'replyCount': currentCount + 1,
          'lastReplyAtMs': now,
        });
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Soft-delete: only the thread author may do this.
  Future<void> deleteThread(String threadId) async {
    try {
      final authUid = _requireAuthUid();
      final ref = _threadsCol.doc(threadId);
      final snap = await ref.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 10));
      if (!snap.exists) return;

      final authorId = (snap.data()?['authorId'] as String? ?? '').trim();
      if (authorId != authUid) {
        throw const DiscussionsRepositoryException('You can only delete your own discussion.');
      }

      await ref.update(<String, dynamic>{'deleted': true}).timeout(const Duration(seconds: 15));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Soft-delete: only the reply author may do this.
  Future<void> deleteReply({required String threadId, required String replyId}) async {
    try {
      final authUid = _requireAuthUid();
      final ref = _repliesCol(threadId).doc(replyId);
      final snap = await ref.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 10));
      if (!snap.exists) return;

      final authorId = (snap.data()?['authorId'] as String? ?? '').trim();
      if (authorId != authUid) {
        throw const DiscussionsRepositoryException('You can only delete your own reply.');
      }

      await ref.update(<String, dynamic>{'deleted': true}).timeout(const Duration(seconds: 15));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }
}
