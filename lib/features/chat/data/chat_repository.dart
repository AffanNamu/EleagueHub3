import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';

import '../../marketplace/data/cloudinary_upload_service.dart';
import '../models/chat_message.dart';

class ChatRepository {
  ChatRepository({
    FirebaseFirestore? firestore,
    CloudinaryUploadService? cloudinary,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _cloudinary = cloudinary ?? CloudinaryUploadService();

  final FirebaseFirestore _firestore;
  final CloudinaryUploadService _cloudinary;

  // ===== Firestore paths =====

  CollectionReference<Map<String, dynamic>> _leagueChatCol(String leagueId) {
    return _firestore.collection('leagues').doc(leagueId).collection('chatroom');
  }

  CollectionReference<Map<String, dynamic>> get _globalChatCol => _firestore.collection('globalChatroom');

  DocumentReference<Map<String, dynamic>> globalChatRequestDoc(String uid) {
    // 1 request per user (requestId == uid)
    return _firestore.collection('globalChatRequests').doc(uid);
  }

  // ===== Streams =====

  Stream<List<ChatMessage>> leagueChatStream(String leagueId, {int limit = 100}) {
    return _leagueChatCol(leagueId)
        .orderBy('createdAtMs', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(ChatMessage.fromDoc).toList());
  }

  Stream<List<ChatMessage>> globalChatStream({int limit = 120}) {
    return _globalChatCol
        .orderBy('createdAtMs', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(ChatMessage.fromDoc).toList());
  }

  // ===== Cloudinary upload (PRODUCTION, using your existing service) =====

  Future<String> uploadLeagueChatImage({
    required String leagueId,
    required PlatformFile file,
  }) {
    return _cloudinary.uploadChatImage(
      file: file,
      folder: 'eleaguehub/chatrooms/leagues/$leagueId',
    );
  }

  Future<String> uploadGlobalChatImage({
    required PlatformFile file,
  }) {
    return _cloudinary.uploadChatImage(
      file: file,
      folder: 'eleaguehub/chatrooms/global',
    );
  }

  // ===== Send messages =====

  Future<void> sendLeagueMessage({
    required String leagueId,
    required String senderId,
    required String senderName,
    required String senderPhoto,
    required String type,
    String text = '',
    String imageUrl = '',
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final doc = _leagueChatCol(leagueId).doc();

    await doc.set(
      <String, dynamic>{
        'messageId': doc.id,
        'senderId': senderId.trim(),
        'senderName': senderName.trim().isEmpty ? 'Player' : senderName.trim(),
        'senderPhoto': senderPhoto.trim(),
        'text': text.trim(),
        'imageUrl': imageUrl.trim(),
        'type': type.trim().isEmpty ? ChatMessageType.text : type.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMs': nowMs,
      },
      SetOptions(merge: false),
    );
  }

  Future<void> sendGlobalMessage({
    required String senderId,
    required String senderName,
    required String senderPhoto,
    required String type,
    String text = '',
    String imageUrl = '',
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final doc = _globalChatCol.doc();

    await doc.set(
      <String, dynamic>{
        'messageId': doc.id,
        'senderId': senderId.trim(),
        'senderName': senderName.trim().isEmpty ? 'Player' : senderName.trim(),
        'senderPhoto': senderPhoto.trim(),
        'text': text.trim(),
        'imageUrl': imageUrl.trim(),
        'type': type.trim().isEmpty ? ChatMessageType.text : type.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMs': nowMs,
      },
      SetOptions(merge: false),
    );
  }
}
