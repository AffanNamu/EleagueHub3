import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessageType {
  static const String text = 'text';
  static const String image = 'image';
  static const String code = 'code';
}

class ChatMessage {
  final String messageId;
  final String senderId;
  final String senderName;
  final String senderPhoto;

  final String text;
  final String imageUrl;
  final String type;

  final Timestamp? createdAt;

  /// Stable ordering field (ms since epoch). Used for ordering queries.
  final int createdAtMs;

  const ChatMessage({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.senderPhoto,
    required this.text,
    required this.imageUrl,
    required this.type,
    required this.createdAt,
    required this.createdAtMs,
  });

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return ChatMessage(
      messageId: (data['messageId'] as String? ?? doc.id).trim(),
      senderId: (data['senderId'] as String? ?? '').trim(),
      senderName: (data['senderName'] as String? ?? '').trim(),
      senderPhoto: (data['senderPhoto'] as String? ?? '').trim(),
      text: (data['text'] as String? ?? '').trim(),
      imageUrl: (data['imageUrl'] as String? ?? '').trim(),
      type: (data['type'] as String? ?? ChatMessageType.text).trim(),
      createdAt: data['createdAt'] is Timestamp ? data['createdAt'] as Timestamp : null,
      createdAtMs: (data['createdAtMs'] is int)
          ? (data['createdAtMs'] as int)
          : ((data['createdAtMs'] is num) ? (data['createdAtMs'] as num).toInt() : 0),
    );
  }
}
