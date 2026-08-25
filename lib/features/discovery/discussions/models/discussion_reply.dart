import 'package:cloud_firestore/cloud_firestore.dart';

/// A reply within a discussion thread.
/// Firestore path: discussion_threads/{threadId}/replies/{replyId}
class DiscussionReply {
  const DiscussionReply({
    required this.replyId,
    required this.threadId,
    required this.authorId,
    required this.authorDisplayName,
    required this.authorPhotoUrl,
    required this.text,
    required this.createdAtMs,
    required this.deleted,
  });

  final String replyId;
  final String threadId;
  final String authorId;
  final String authorDisplayName;
  final String authorPhotoUrl;
  final String text;
  final int createdAtMs;
  final bool deleted;

  factory DiscussionReply.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    return DiscussionReply(
      replyId: doc.id,
      threadId: (map['threadId'] as String? ?? '').trim(),
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
