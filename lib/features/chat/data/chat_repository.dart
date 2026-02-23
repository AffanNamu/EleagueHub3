import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';

import '../../auth/data/user_profile_repository.dart';
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

  CollectionReference<Map<String, dynamic>> get _globalChatCol => _firestore.collection('globalChatroom');

  DocumentReference<Map<String, dynamic>> globalChatRequestDoc(String uid) {
    return _firestore.collection('globalChatRequests').doc(uid);
  }

  DocumentReference<Map<String, dynamic>> get _appAdminsDoc => _firestore.collection('app').doc('admins');

  Stream<DocumentSnapshot<Map<String, dynamic>>> appAdminsDocStream() {
    return _appAdminsDoc.snapshots();
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

  Stream<ChatMessage?> leaguePinnedMessageStream(String leagueId) {
    return _leagueChatCol(leagueId)
        .where('pinned', isEqualTo: true)
        .orderBy('pinnedAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty ? null : ChatMessage.fromDoc(snap.docs.first));
  }

  Stream<ChatMessage?> globalPinnedMessageStream() {
    return _globalChatCol
        .where('pinned', isEqualTo: true)
        .orderBy('pinnedAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty ? null : ChatMessage.fromDoc(snap.docs.first));
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

  Future<String> uploadLeagueChatVoice({
    required String leagueId,
    required PlatformFile file,
  }) {
    return _cloudinary.uploadChatVoice(
      file: file,
      folder: 'chat_voice_messages/$leagueId',
    );
  }

  // ===== Resolve sender display info from Firestore profile =====

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

      final resolvedName = profile.teamName.trim().isNotEmpty ? profile.teamName.trim() : fallbackName;

      String resolvedPhoto = fallbackPhoto;
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
      } catch (_) {}

      return (name: resolvedName, photo: resolvedPhoto);
    } catch (_) {
      return (name: fallbackName, photo: fallbackPhoto);
    }
  }

  // ===== Send messages (now supports replies) =====

  Future<void> sendLeagueMessage({
    required String leagueId,
    required String senderId,
    required String senderName,
    required String senderPhoto,
    required String type,
    String text = '',
    String imageUrl = '',
    String voiceUrl = '',

    /// Optional: provide a messageId to keep client-side correlation (e.g., push notifications).
    String messageIdOverride = '',

    // Reply payload (optional)
    String replyToMessageId = '',
    String replyToSenderName = '',
    String replyToText = '',
    String replyToType = '',
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final col = _leagueChatCol(leagueId);
    final doc = messageIdOverride.trim().isNotEmpty ? col.doc(messageIdOverride.trim()) : col.doc();

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
        'voiceUrl': voiceUrl.trim(),
        'type': type.trim().isEmpty ? ChatMessageType.text : type.trim(),
        'leagueId': leagueId.trim(),
        'timestamp': nowMs,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMs': nowMs,

        // Pin/mod defaults
        'pinned': false,
        'pinnedAt': null,
        'pinnedBy': '',
        'deleted': false,
        'deletedAt': null,
        'deletedBy': '',

        // Reply fields (always present; empty means "no reply")
        'replyToMessageId': replyToMessageId.trim(),
        'replyToSenderName': replyToSenderName.trim(),
        'replyToText': replyToText.trim(),
        'replyToType': replyToType.trim(),
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
    String voiceUrl = '',

    // Reply payload (optional)
    String replyToMessageId = '',
    String replyToSenderName = '',
    String replyToText = '',
    String replyToType = '',
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
        'voiceUrl': voiceUrl.trim(),
        'type': type.trim().isNotEmpty ? type.trim() : ChatMessageType.text,
        'timestamp': nowMs,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtMs': nowMs,

        // Pin/mod defaults
        'pinned': false,
        'pinnedAt': null,
        'pinnedBy': '',
        'deleted': false,
        'deletedAt': null,
        'deletedBy': '',

        // Reply fields
        'replyToMessageId': replyToMessageId.trim(),
        'replyToSenderName': replyToSenderName.trim(),
        'replyToText': replyToText.trim(),
        'replyToType': replyToType.trim(),
      },
      SetOptions(merge: false),
    );
  }

  // ===== Pinning =====

  Future<void> pinLeagueMessage({
    required String leagueId,
    required String messageId,
    required String pinnedBy,
  }) async {
    final col = _leagueChatCol(leagueId);
    final targetRef = col.doc(messageId);

    final prevPinnedSnap = await col.where('pinned', isEqualTo: true).orderBy('pinnedAt', descending: true).limit(1).get();

    final prevRef = prevPinnedSnap.docs.isEmpty ? null : prevPinnedSnap.docs.first.reference;

    final batch = _firestore.batch();

    if (prevRef != null && prevRef.id != messageId) {
      batch.update(prevRef, <String, dynamic>{
        'pinned': false,
        'pinnedAt': null,
        'pinnedBy': '',
      });
    }

    batch.update(targetRef, <String, dynamic>{
      'pinned': true,
      'pinnedAt': FieldValue.serverTimestamp(),
      'pinnedBy': pinnedBy.trim(),
    });

    await batch.commit();
  }

  Future<void> pinGlobalMessage({
    required String messageId,
    required String pinnedBy,
    bool unpinPrevious = true,
  }) async {
    final col = _globalChatCol;
    final targetRef = col.doc(messageId);

    if (!unpinPrevious) {
      await targetRef.update(<String, dynamic>{
        'pinned': true,
        'pinnedAt': FieldValue.serverTimestamp(),
        'pinnedBy': pinnedBy.trim(),
      });
      return;
    }

    final prevPinnedSnap = await col.where('pinned', isEqualTo: true).orderBy('pinnedAt', descending: true).limit(1).get();

    final prevRef = prevPinnedSnap.docs.isEmpty ? null : prevPinnedSnap.docs.first.reference;

    final batch = _firestore.batch();

    if (prevRef != null && prevRef.id != messageId) {
      batch.update(prevRef, <String, dynamic>{
        'pinned': false,
        'pinnedAt': null,
        'pinnedBy': '',
      });
    }

    batch.update(targetRef, <String, dynamic>{
      'pinned': true,
      'pinnedAt': FieldValue.serverTimestamp(),
      'pinnedBy': pinnedBy.trim(),
    });

    await batch.commit();
  }

  // ===== Moderation delete (soft delete) =====

  Future<void> softDeleteLeagueMessage({
    required String leagueId,
    required String messageId,
    required String deletedBy,
  }) async {
    await _leagueChatCol(leagueId).doc(messageId).update(<String, dynamic>{
      'deleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': deletedBy.trim(),
      'pinned': false,
      'pinnedAt': null,
      'pinnedBy': '',
    });
  }

  Future<void> softDeleteGlobalMessage({
    required String messageId,
    required String deletedBy,
  }) async {
    await _globalChatCol.doc(messageId).update(<String, dynamic>{
      'deleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedBy': deletedBy.trim(),
      'pinned': false,
      'pinnedAt': null,
      'pinnedBy': '',
    });
  }

  // ===== Legacy hard delete (compat) =====

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
