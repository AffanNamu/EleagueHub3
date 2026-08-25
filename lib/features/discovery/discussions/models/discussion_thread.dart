import 'package:cloud_firestore/cloud_firestore.dart';

/// A community discussion thread (Community pillar — Discussions).
/// Firestore path: discussion_threads/{threadId}
///
/// Kept fully separate from public_posts (Public Feed) and statuses —
/// this is durable, topic-based community conversation, not a
/// chronological feed or a temporary update. Open to any signed-in
/// user (not Pro/Elite-gated) since Discussions is about community
/// engagement rather than promotional content.
class DiscussionThread {
  const DiscussionThread({
    required this.threadId,
    required this.authorId,
    required this.authorDisplayName,
    required this.authorPhotoUrl,
    required this.title,
    required this.body,
    required this.createdAtMs,
    required this.lastReplyAtMs,
    required this.replyCount,
    required this.deleted,
  });

  final String threadId;
  final String authorId;
  final String authorDisplayName;
  final String authorPhotoUrl;
  final String title;
  final String body;
  final int createdAtMs;
  final int lastReplyAtMs;
  final int replyCount;
  final bool deleted;

  factory DiscussionThread.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    return DiscussionThread(
      threadId: doc.id,
      authorId: (map['authorId'] as String? ?? '').trim(),
      authorDisplayName: (map['authorDisplayName'] as String? ?? '').trim(),
      authorPhotoUrl: (map['authorPhotoUrl'] as String? ?? '').trim(),
      title: (map['title'] as String? ?? '').trim(),
      body: (map['body'] as String? ?? '').trim(),
      createdAtMs: _asInt(map['createdAtMs']),
      lastReplyAtMs: _asInt(map['lastReplyAtMs']),
      replyCount: _asInt(map['replyCount']),
      deleted: map['deleted'] == true,
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}
