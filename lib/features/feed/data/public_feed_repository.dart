// lib/features/feed/data/public_feed_repository.dart
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/public_post.dart';

class PublicFeedRepositoryException implements Exception {
  final String message;
  const PublicFeedRepositoryException(this.message);

  @override
  String toString() => message;
}

/// Data layer for Feature 3 — the Public Feed.
/// Firestore path: public_posts/{postId}
class PublicFeedRepository {
  PublicFeedRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _postsCol =>
      _firestore.collection('public_posts');

  String _requireAuthUid() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const PublicFeedRepositoryException('Please sign in and try again.');
    }
    return uid;
  }

  Never _rethrowFriendly(Object e) {
    if (e is PublicFeedRepositoryException) throw e;
    if (e is SocketException) {
      throw const PublicFeedRepositoryException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    }
    if (e is TimeoutException) {
      throw const PublicFeedRepositoryException(
        'Your internet connection seems unstable. Please try again.',
      );
    }
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          throw const PublicFeedRepositoryException(
            'You do not have permission to do that. A Pro or Elite plan is required to post.',
          );
        case 'unavailable':
        case 'deadline-exceeded':
          throw const PublicFeedRepositoryException(
            'Your network appears to be offline. Please check your connection and try again.',
          );
        default:
          throw const PublicFeedRepositoryException(
            "We couldn't complete this action. Please try again.",
          );
      }
    }
    throw const PublicFeedRepositoryException('Something went wrong. Please try again.');
  }

  /// Creates a text or competition-promo post for the currently
  /// signed-in user. Match-result posts are intentionally not exposed
  /// here yet (no UI collects a score today) — the model supports it
  /// for a future addition without a schema change.
  Future<void> createPost({
    required String authorDisplayName,
    required String authorPhotoUrl,
    required String text,
    String mediaUrl = '',
    PublicPostType postType = PublicPostType.text,
    String leagueId = '',
    String leagueName = '',
  }) async {
    try {
      final authUid = _requireAuthUid();
      final trimmedText = text.trim();
      if (trimmedText.isEmpty && mediaUrl.trim().isEmpty) {
        throw const PublicFeedRepositoryException(
          'Please add some text or an image to your post.',
        );
      }

      final ref = _postsCol.doc();
      final now = DateTime.now().millisecondsSinceEpoch;

      await ref.set(<String, dynamic>{
        'postId': ref.id,
        'authorId': authUid,
        'authorDisplayName': authorDisplayName.trim(),
        'authorPhotoUrl': authorPhotoUrl.trim(),
        'createdAtMs': now,
        'text': trimmedText.length > 2000 ? trimmedText.substring(0, 2000) : trimmedText,
        'mediaUrl': mediaUrl.trim(),
        'postType': postType.storageValue,
        'leagueId': leagueId.trim(),
        'leagueName': leagueName.trim(),
        'matchScoreHome': 0,
        'matchScoreAway': 0,
        'matchOpponentName': '',
        'isPromoted': false,
        'likeCount': 0,
        'commentCount': 0,
        'deleted': false,
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// "For You" == chronological feed for now (identical to Latest).
  /// Kept as a separate method so a real ranking algorithm can replace
  /// its internals later without changing call sites.
  Stream<List<PublicPost>> watchForYouFeed({int limit = 30}) {
    return _postsCol
        .where('deleted', isEqualTo: false)
        .orderBy('createdAtMs', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(PublicPost.fromDoc).toList(growable: false))
        .handleError((_) {});
  }

  Stream<List<PublicPost>> watchLatestFeed({int limit = 30}) {
    return watchForYouFeed(limit: limit);
  }

  Future<bool> hasLiked(String postId) async {
    try {
      final authUid = _requireAuthUid();
      final doc = await _postsCol
          .doc(postId)
          .collection('likes')
          .doc(authUid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  Future<void> toggleLike(String postId) async {
    try {
      final authUid = _requireAuthUid();
      final postRef = _postsCol.doc(postId);
      final likeRef = postRef.collection('likes').doc(authUid);

      await _firestore.runTransaction((txn) async {
        final likeSnap = await txn.get(likeRef);
        final postSnap = await txn.get(postRef);
        if (!postSnap.exists) return;

        final currentCount =
            ((postSnap.data() ?? {})['likeCount'] as num?)?.toInt() ?? 0;

        if (likeSnap.exists) {
          txn.delete(likeRef);
          txn.update(postRef, {
            'likeCount': (currentCount - 1).clamp(0, 1 << 31),
          });
        } else {
          txn.set(likeRef, {
            'userId': authUid,
            'likedAtMs': DateTime.now().millisecondsSinceEpoch,
          });
          txn.update(postRef, {'likeCount': currentCount + 1});
        }
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Soft-delete: only the author may do this. Matches the pattern
  /// used elsewhere in the app (chat soft-delete) rather than a hard
  /// delete, so counts/links referencing the post don't break.
  Future<void> deletePost(String postId) async {
    try {
      final authUid = _requireAuthUid();
      final ref = _postsCol.doc(postId);
      final snap = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      if (!snap.exists) return;
      final authorId = (snap.data()?['authorId'] as String? ?? '').trim();
      if (authorId != authUid) {
        throw const PublicFeedRepositoryException('You can only delete your own posts.');
      }

      await ref.update(<String, dynamic>{
        'deleted': true,
      }).timeout(const Duration(seconds: 15));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }
}
