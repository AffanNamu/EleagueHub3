// lib/features/chat/models/private_message.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'chat_message.dart' show ChatDeliveryStatus;

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
    this.deliveryStatus = ChatDeliveryStatus.sent,
    this.deliveredAtMs = 0,
    this.seenAtMs = 0,
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

  /// Local-only send status for optimistic UI. Never persisted to
  /// Firestore and never set by [fromDoc] (always [ChatDeliveryStatus.sent]
  /// there) -- only the sender's own device ever constructs a
  /// sending/failed instance.
  final ChatDeliveryStatus deliveryStatus;

  /// Set once by the RECIPIENT (never the sender -- enforced by
  /// firestore.rules) the moment their device syncs this message via its
  /// own live listener -- see PrivateChatRepository.markDelivered(). 0
  /// means not yet delivered. Write-once: never cleared or rewritten
  /// once set.
  final int deliveredAtMs;

  /// Set once by the RECIPIENT when they've actually had this thread open
  /// for a moment with the message loaded -- see
  /// PrivateChatRepository.markSeen(). 0 means not yet seen. Write-once,
  /// same as [deliveredAtMs].
  final int seenAtMs;

  PrivateMessage copyWith({ChatDeliveryStatus? deliveryStatus}) => PrivateMessage(
        id: id,
        senderId: senderId,
        type: type,
        text: text,
        imageUrl: imageUrl,
        voiceUrl: voiceUrl,
        voiceDurationMs: voiceDurationMs,
        createdAtMs: createdAtMs,
        deliveryStatus: deliveryStatus ?? this.deliveryStatus,
        deliveredAtMs: deliveredAtMs,
        seenAtMs: seenAtMs,
      );

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
      deliveredAtMs: _asInt(map['deliveredAtMs']),
      seenAtMs: _asInt(map['seenAtMs']),
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}
