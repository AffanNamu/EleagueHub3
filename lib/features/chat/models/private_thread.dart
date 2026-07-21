// lib/features/chat/models/private_thread.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class PrivateThread {
  const PrivateThread({
    required this.id,
    required this.participantIds,
    required this.initiatedBy,
    required this.lastMessage,
    required this.lastMessageAtMs,
    required this.lastSenderId,
    required this.createdAtMs,
  });

  final String id;
  final List<String> participantIds;
  final String initiatedBy;
  final String lastMessage;
  final int lastMessageAtMs;
  final String lastSenderId;
  final int createdAtMs;

  String otherParticipant(String selfUid) {
    return participantIds.firstWhere(
      (id) => id != selfUid,
      orElse: () => '',
    );
  }

  factory PrivateThread.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    final rawIds = (map['participantIds'] as List?) ?? const [];
    return PrivateThread(
      id: doc.id,
      participantIds: rawIds.map((e) => '$e').toList(growable: false),
      initiatedBy: (map['initiatedBy'] as String? ?? '').trim(),
      lastMessage: (map['lastMessage'] as String? ?? '').trim(),
      lastMessageAtMs: _asInt(map['lastMessageAtMs']),
      lastSenderId: (map['lastSenderId'] as String? ?? '').trim(),
      createdAtMs: _asInt(map['createdAtMs']),
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}
