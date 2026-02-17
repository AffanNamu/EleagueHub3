import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';

import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../../marketplace/data/cloudinary_upload_service.dart';
import '../models/chat_message.dart';

class ChatRepository {
  ChatRepository({
    FirebaseFirestore? firestore,
    CloudinaryUploadService? cloudinary,
    UserProfileRepository? profileRepo,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _cloudinary = cloudinary ?? CloudinaryUploadService(),
        _profileRepo = profileRepo ?? UserProfileRepository();

  final FirebaseFirestore _firestore;
  final CloudinaryUploadService _cloudinary;
  final UserProfileRepository _profileRepo;

  // ===== Firestore paths =====

  CollectionReference<Map<String, dynamic>> _leagueChatCol(String leagueId) {
    return _firestore.collection('leagues').doc(leagueId).collection('chatroom');
  }

  CollectionReference<Map<String, dynamic>> get _globalChatCol =>
      _firestore.collection('globalChatroom');

  DocumentReference<Map<String, dynamic>> globalChatRequestDoc(String uid) {
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

  // ===== Cloudinary upload =====

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

  // ===== Resolve sender display info from Firestore profile =====

  /// Fetches the user's Firestore profile and returns (teamName, photoUrl).
  /// Falls back to the provided defaults if the profile is missing or fields are empty.
  Future<({String name, String photo})> resolveSenderIdentity({
    required String uid,
    required String fallbackName,
    required String fallbackPhoto,
  }) async {
    try {
      final profile = await _profileRepo.fetchByUserId(uid);
      if (profile == null) {
        return (name: fallbackName, photo: fallbackPhoto);
      }

      // Prefer teamName from Firestore profile.
      final resolvedName = profile.teamName.trim().isNotEmpty
          ? profile.teamName.trim()
          : fallbackName;

      // Prefer profile photo from Firestore (check multiple fields).
      String resolvedPhoto = fallbackPhoto;
      // Try to read photoUrl / profileImageUrl / teamImageUrl dynamically.
      try {
        final doc = await _firestore.collection('users').doc(uid).get();
        final data = doc.data();
        if (data != null) {
          final p1 = (data['photoUrl'] as String? ?? '').trim();
          final p2 = (data['profileImageUrl'] as String? ?? '').trim();
          final p3 = (data['teamImageUrl'] as String? ?? '').trim();
          if (p1.isNotEmpty) {
            resolvedPhoto = p1;
          } else if (p2.isNotEmpty) {
            resolvedPhoto = p2;
          } else if (p3.isNotEmpty) {
            resolvedPhoto = p3;
          }
        }
      } catch (_) {
        // Ignore — use fallback.
      }

      return (name: resolvedName, photo: resolvedPhoto);
    } catch (_) {
      return (name: fallbackName, photo: fallbackPhoto);
    }
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

    final safeName = senderName.trim().isEmpty ? 'Player' : senderName.trim();
    final safePhoto = senderPhoto.trim();

    await doc.set(
      <String, dynamic>{
        'messageId': doc.id,
        'senderId': senderId.trim(),
        'senderName': safeName,
        'senderPhoto': safePhoto,
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

    final safeName = senderName.trim().isEmpty ? 'Player' : senderName.trim();
    final safePhoto = senderPhoto.trim();

    await doc.set(
      <String, dynamic>{
        'messageId': doc.id,
        'senderId': senderId.trim(),
        'senderName': safeName,
        'senderPhoto': safePhoto,
        'text': text.trim(),
        'imageUrl': imageUrl.trim(),
        'type': type.trim().isEmpty ? ChatMessageType.text : type.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMs': nowMs,
      },
      SetOptions(merge: false),
    );
  }

  // ===== Delete message (moderation) =====

  Future<void> deleteGlobalMessage(String messageId) async {
    await _globalChatCol.doc(messageId).delete();
  }

  Future<void> deleteLeagueMessage({
    required String leagueId,
    required String messageId,
  }) async {
    await _leagueChatCol(leagueId).doc(messageId).delete();
  }
}
