// lib/features/chat/models/private_message.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum PrivateMessageType { text, image, voice }

extension PrivateMessageTypeX on PrivateMessageType {
  String get value => name;

  static PrivateMessageType fromString(String? raw) {
    switch (raw) {
      case 'image':
        return PrivateMessageType.image;
      case 'voice':
        return PrivateMessageType.voice;
      case 'text':
      default:
        return PrivateMessageType.text;
    }
  }
}

class PrivateMessage {
  const PrivateMessage({
    required this.id,
    required this.senderId,
    required this.type,
    required this.text,
    required this.imageUrl,
    required this.voiceUrl,
    this.voiceDurationMs = 0,
    required this.createdAtMs,
  });

  final String id;
  final String senderId;
  final PrivateMessageType type;
  final String text;
  final String imageUrl;
  final String voiceUrl;

  /// Duration of the voice note in milliseconds, captured at send time.
  /// 0 for messages sent before this field existed.
  final int voiceDurationMs;

  final int createdAtMs;

  factory PrivateMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    return PrivateMessage(
      id: doc.id,
      senderId: (map['senderId'] as String? ?? '').trim(),
      type: PrivateMessageTypeX.fromString(map['type'] as String?),
      text: (map['text'] as String? ?? '').trim(),
      imageUrl: (map['imageUrl'] as String? ?? '').trim(),
      voiceUrl: (map['voiceUrl'] as String? ?? '').trim(),
      voiceDurationMs: _asInt(map['voiceDurationMs']),
      createdAtMs: _asInt(map['createdAtMs']),
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}
