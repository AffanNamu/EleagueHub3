import 'package:cloud_firestore/cloud_firestore.dart';

/// A comment on a Public Feed post.
/// Firestore path: public_posts/{postId}/comments/{commentId}
///
/// NEW (comment bug #4): there was previously no comment infrastructure
/// at all for the Public Feed -- no model, no repository methods, no
/// subcollection rules, and the comment button in the UI had no tap
/// handler. This is a from-scratch addition, deliberately mirroring the
/// existing `likes` subcollection pattern (one doc per comment, a
/// denormalized `commentCount` on the parent post kept in sync by the
/// same transaction that creates the comment) so it stays consistent
/// with how likes and discussion-thread replies already work in this
/// codebase.
class PublicPostComment {
  const PublicPostComment({
    required this.commentId,
    required this.postId,
    required this.authorId,
    required this.authorDisplayName,
    required this.authorPhotoUrl,
    required this.text,
    required this.createdAtMs,
    required this.deleted,
  });

  final String commentId;
  final String postId;
  final String authorId;
  final String authorDisplayName;
  final String authorPhotoUrl;
  final String text;
  final int createdAtMs;
  final bool deleted;

  factory PublicPostComment.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final map = doc.data() ?? <String, dynamic>{};
    return PublicPostComment(
      commentId: doc.id,
      postId: (map['postId'] as String? ?? '').trim(),
      authorId: (map['authorId'] as String? ?? '').trim(),
      authorDisplayName: (map['authorDisplayName'] as String? ?? '').trim(),
      authorPhotoUrl: (map['authorPhotoUrl'] as String? ?? '').trim(),
      text: (map['text'] as String? ?? '').trim(),
      createdAtMs: _asInt(map['createdAtMs']),
      deleted: map['deleted'] == true,
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}
