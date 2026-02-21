import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessageType {
  static const String text = 'text';
  static const String image = 'image';
  static const String code = 'code';
  static const String voice = 'voice';
}

class ChatMessage {
  final String messageId;
  final String senderId;
  final String senderName;
  final String senderPhoto;

  final String text;
  final String imageUrl;
  final String voiceUrl;
  final String type;

  final Timestamp? createdAt;

  /// Stable ordering field (ms since epoch). Used for ordering queries.
  final int createdAtMs;

  /// Optional (added without breaking existing structure)
  /// League messages store leagueId, global messages store ''.
  final String leagueId;

  /// Optional stable timestamp (ms) used by existing code.
  final int timestamp;

  // ===== Moderation / pinning (NEW) =====
  final bool pinned;
  final Timestamp? pinnedAt;
  final String pinnedBy;

  final bool deleted;
  final Timestamp? deletedAt;
  final String deletedBy;

  const ChatMessage({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.senderPhoto,
    required this.text,
    required this.imageUrl,
    required this.voiceUrl,
    required this.type,
    required this.createdAt,
    required this.createdAtMs,
    required this.leagueId,
    required this.timestamp,
    required this.pinned,
    required this.pinnedAt,
    required this.pinnedBy,
    required this.deleted,
    required this.deletedAt,
    required this.deletedBy,
  });

  bool get hasText => text.trim().isNotEmpty;

  String get displaySenderName =>
      senderName.trim().isEmpty ? 'Player' : senderName.trim();

  String pinnedPreview() {
    if (deleted) return 'This message was deleted';
    switch (type) {
      case ChatMessageType.image:
        return hasText ? text.trim() : 'Photo';
      case ChatMessageType.voice:
        return hasText ? text.trim() : 'Voice message';
      case ChatMessageType.code:
        return hasText ? text.trim() : 'Code';
      case ChatMessageType.text:
      default:
        return hasText ? text.trim() : 'Message';
    }
  }

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    Timestamp? _ts(dynamic v) => v is Timestamp ? v : null;

    int _int(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return 0;
    }

    bool _bool(dynamic v) {
      if (v is bool) return v;
      return false;
    }

    String _str(dynamic v) => (v is String ? v : '').trim();

    return ChatMessage(
      messageId: _str(data['messageId']).isNotEmpty ? _str(data['messageId']) : doc.id,
      senderId: _str(data['senderId']),
      senderName: _str(data['senderName']),
      senderPhoto: _str(data['senderPhoto']),
      text: _str(data['text']),
      imageUrl: _str(data['imageUrl']),
      voiceUrl: _str(data['voiceUrl']),
      type: _str(data['type']).isNotEmpty ? _str(data['type']) : ChatMessageType.text,
      createdAt: _ts(data['createdAt']),
      createdAtMs: _int(data['createdAtMs']),
      leagueId: _str(data['leagueId']),
      timestamp: _int(data['timestamp']),
      pinned: _bool(data['pinned']),
      pinnedAt: _ts(data['pinnedAt']),
      pinnedBy: _str(data['pinnedBy']),
      deleted: _bool(data['deleted']),
      deletedAt: _ts(data['deletedAt']),
      deletedBy: _str(data['deletedBy']),
    );
  }
}
