// lib/features/feed/data/public_feed_repository.dart
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/public_post.dart';
import '../models/public_post_comment.dart';

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

  CollectionReference<Map<String, dynamic>> _commentsCol(String postId) =>
      _postsCol.doc(postId).collection('comments');

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
    String audioUrl = '', // NEW: Audio support
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
        'audioUrl': audioUrl.trim(), // NEW: Audio support
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
  /// FIX: Removed `where('deleted', isEqualTo: false)` from the Firestore
  /// query to avoid missing composite index errors (which caused the infinite spin).
  /// Deletions are now securely filtered client-side.
  Stream<List<PublicPost>> watchForYouFeed({int limit = 30}) {
    return _postsCol
        .orderBy('createdAtMs', descending: true)
        .limit(limit + 10) // fetch extra to account for client-side filtering
        .snapshots()
        .map((snap) => snap.docs
            .map(PublicPost.fromDoc)
            .where((post) => !post.deleted) // Client-side filter prevents index crashes
            .take(limit)
            .toList(growable: false))
        .handleError((e) {
          // Allow UI to see the error if something else breaks
          throw e;
        });
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

  // ── Comments (Feature 3, comment bug #4) ─────────────────────────────────
  //
  // NEW: this repository previously had no comment support whatsoever.
  // Added here following the exact same shape as toggleLike() above —
  // a subcollection doc per comment, plus a denormalized commentCount
  // on the parent post kept in sync by the same transaction that
  // writes the comment. Read is public (matches posts/likes); creating
  // a comment requires being signed in (comments are NOT Pro/Elite
  // gated — only creating the original post is).

  /// Live comments for a post, oldest first, with soft-deleted comments
  /// filtered out client-side (same pattern as watchForYouFeed's
  /// `deleted` filtering, to avoid needing a composite index).
  Stream<List<PublicPostComment>> watchComments(String postId, {int limit = 200}) {
    return _commentsCol(postId)
        .orderBy('createdAtMs', descending: false)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map(PublicPostComment.fromDoc)
            .where((c) => !c.deleted)
            .toList(growable: false))
        .handleError((e) {
      throw e;
    });
  }

  Future<void> addComment({
    required String postId,
    required String authorDisplayName,
    required String authorPhotoUrl,
    required String text,
  }) async {
    try {
      final authUid = _requireAuthUid();
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        throw const PublicFeedRepositoryException('Please write a comment first.');
      }

      final postRef = _postsCol.doc(postId);
      final commentRef = postRef.collection('comments').doc();
      final now = DateTime.now().millisecondsSinceEpoch;
      final safeText = trimmed.length > 500 ? trimmed.substring(0, 500) : trimmed;

      await _firestore.runTransaction((txn) async {
        final postSnap = await txn.get(postRef);
        if (!postSnap.exists) {
          throw const PublicFeedRepositoryException('This post no longer exists.');
        }
        final postData = postSnap.data() ?? <String, dynamic>{};
        if (postData['deleted'] == true) {
          throw const PublicFeedRepositoryException('This post no longer exists.');
        }
        final currentCount = (postData['commentCount'] as num?)?.toInt() ?? 0;

        txn.set(commentRef, <String, dynamic>{
          'commentId': commentRef.id,
          'postId': postId,
          'authorId': authUid,
          'authorDisplayName': authorDisplayName.trim(),
          'authorPhotoUrl': authorPhotoUrl.trim(),
          'text': safeText,
          'createdAtMs': now,
          'deleted': false,
        });
        txn.update(postRef, {'commentCount': currentCount + 1});
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Soft-delete: the comment's own author only (matches the post
  /// soft-delete pattern). commentCount is intentionally left as-is,
  /// same choice already made for discussion_threads' replyCount.
  Future<void> deleteComment({
    required String postId,
    required String commentId,
  }) async {
    try {
      final authUid = _requireAuthUid();
      final ref = _commentsCol(postId).doc(commentId);
      final snap = await ref.get(const GetOptions(source: Source.server)).timeout(
            const Duration(seconds: 10),
          );
      if (!snap.exists) return;
      final authorId = (snap.data()?['authorId'] as String? ?? '').trim();
      if (authorId != authUid) {
        throw const PublicFeedRepositoryException('You can only delete your own comments.');
      }
      await ref.update(<String, dynamic>{'deleted': true}).timeout(const Duration(seconds: 15));
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
