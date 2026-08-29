//chat/data/private_chat_repository.dart
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../auth/data/user_profile_repository.dart';
import '../../marketplace/data/cloudinary_upload_service.dart';
import '../../profile/data/team_profile_repository.dart';
import '../models/private_message.dart';
import '../models/private_thread.dart';

enum PrivateChatAccess {
  /// A thread already exists — either side can open/reply freely.
  threadExists,
  /// No thread yet, but the viewer has an active paid plan and can start one.
  canStart,
  /// No thread yet, and the viewer is free — cannot start, must wait
  /// for the other user to message first.
  locked,
  /// Either party has blocked the other — messaging is unavailable
  /// regardless of plan status, and the button should not be shown
  /// at all (not even as a disabled/upgrade state).
  blocked,
}

class PrivateChatAccessResult {
  const PrivateChatAccessResult({required this.access, this.existingThreadId});
  final PrivateChatAccess access;
  final String? existingThreadId;
}

class PrivateChatException implements Exception {
  final String message;
  const PrivateChatException(this.message);

  @override
  String toString() => message;
}

class PrivateChatRepository {
  PrivateChatRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    CloudinaryUploadService? cloudinary,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _cloudinary = cloudinary ?? CloudinaryUploadService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final CloudinaryUploadService _cloudinary;
  final UserProfileRepository _userProfiles = UserProfileRepository();
  final TeamProfileRepository _teamProfiles = TeamProfileRepository();

  CollectionReference<Map<String, dynamic>> get _threads =>
      _firestore.collection('private_threads');

  String _requireAuthUid() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const PrivateChatException('Please sign in and try again.');
    }
    return uid;
  }

  Never _rethrowFriendly(Object e) {
    if (e is PrivateChatException) throw e;
    if (e is SocketException) {
      throw const PrivateChatException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    }
    if (e is TimeoutException) {
      throw const PrivateChatException(
        'Your internet connection seems unstable. Please try again.',
      );
    }
    if (e is FirebaseException) {
      switch (e.code) {
        case 'permission-denied':
          throw const PrivateChatException(
            'Private chat requires Premium to start a new conversation.',
          );
        case 'unavailable':
        case 'deadline-exceeded':
          throw const PrivateChatException(
            'Your network appears to be offline. Please check your connection and try again.',
          );
        default:
          throw const PrivateChatException(
            "We couldn't complete this action. Please try again.",
          );
      }
    }
    throw const PrivateChatException('Something went wrong. Please try again.');
  }

  /// Deterministic thread id for a pair of users — avoids duplicate
  /// threads and lets rules validate participantIds cheaply.
  String _threadIdFor(String uidA, String uidB) {
    final sorted = [uidA, uidB]..sort();
    return 'dm_${sorted[0]}_${sorted[1]}';
  }

  /// Determines whether the signed-in user can message [otherUserId]
  /// right now, without attempting a write (so the UI can show the
  /// correct button state instead of surfacing a permission error).
  Future<PrivateChatAccessResult> checkAccess(String otherUserId) async {
    try {
      final authUid = _requireAuthUid();
      final other = otherUserId.trim();
      if (other.isEmpty || other == authUid) {
        return const PrivateChatAccessResult(access: PrivateChatAccess.locked);
      }

      final blocked = await _teamProfiles.isBlockedEitherWay(other);
      if (blocked) {
        return const PrivateChatAccessResult(access: PrivateChatAccess.blocked);
      }

      final threadId = _threadIdFor(authUid, other);

      // A thread doc that doesn't exist yet is denied by the `get` rule
      // (resource.data is null), so permission-denied here means "no
      // thread exists" rather than a real access problem — treat it as such.
      bool threadExists = false;
      try {
        final doc = await _threads
            .doc(threadId)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 10));
        threadExists = doc.exists;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
        threadExists = false;
      }

      if (threadExists) {
        return PrivateChatAccessResult(
          access: PrivateChatAccess.threadExists,
          existingThreadId: threadId,
        );
      }

      final profile = await _userProfiles.fetchByUserId(authUid);
      final canStart = profile?.hasPlanActive ?? false;

      return PrivateChatAccessResult(
        access: canStart ? PrivateChatAccess.canStart : PrivateChatAccess.locked,
      );
    } catch (_) {
      // Fail closed to "locked" rather than showing a button that will
      // error on tap.
      return const PrivateChatAccessResult(access: PrivateChatAccess.locked);
    }
  }

  /// Starts a new thread with [otherUserId], or returns the existing one.
  ///
  /// FREE users cannot start a new thread — this is enforced both here
  /// (fast, friendly error) and in Firestore rules (authoritative).
  /// Once a thread exists, either participant can reply regardless of
  /// their own plan status.
  Future<PrivateThread> startOrGetThread(String otherUserId) async {
    try {
      final authUid = _requireAuthUid();
      final other = otherUserId.trim();
      if (other.isEmpty || other == authUid) {
        throw const PrivateChatException('Invalid recipient.');
      }

      if (await _teamProfiles.isBlockedEitherWay(other)) {
        throw const PrivateChatException('You cannot message this user.');
      }

      final threadId = _threadIdFor(authUid, other);
      final ref = _threads.doc(threadId);

      bool threadExists = false;
      DocumentSnapshot<Map<String, dynamic>>? existing;
      try {
        existing = await ref
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 12));
        threadExists = existing.exists;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
        threadExists = false;
      }

      if (threadExists && existing != null) {
        return PrivateThread.fromDoc(existing);
      }

      // Only the initiator needs an active paid plan. Check via the
      // same authoritative source as the rest of the app.
      final profile = await _userProfiles.fetchByUserId(authUid);
      final canStart = profile?.hasPlanActive ?? false;

      if (!canStart) {
        throw const PrivateChatException(
          'Starting a private chat requires a Premium plan. '
          'Free accounts can reply once a Premium user messages you first.',
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final data = <String, dynamic>{
        'participantIds': [authUid, other]..sort(),
        'initiatedBy': authUid,
        'lastMessage': '',
        'lastMessageAtMs': now,
        'lastSenderId': '',
        'createdAtMs': now,
      };

      await ref.set(data, SetOptions(merge: false)).timeout(const Duration(seconds: 15));

      final fresh = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));
      return PrivateThread.fromDoc(fresh);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Stream<List<PrivateThread>> watchInbox() {
    try {
      final uid = _requireAuthUid();
      return _threads
          .where('participantIds', arrayContains: uid)
          .orderBy('lastMessageAtMs', descending: true)
          .snapshots()
          .map((snap) => snap.docs.map(PrivateThread.fromDoc).toList(growable: false))
          .handleError((_) {});
    } catch (_) {
      return const Stream<List<PrivateThread>>.empty();
    }
  }

  Stream<List<PrivateMessage>> watchMessages(String threadId, {int limit = 100}) {
    try {
      _requireAuthUid();
      return _threads
          .doc(threadId)
          .collection('messages')
          .orderBy('createdAtMs', descending: true)
          .limit(limit)
          .snapshots()
          .map((snap) => snap.docs.map(PrivateMessage.fromDoc).toList(growable: false))
          .handleError((_) {});
    } catch (_) {
      return const Stream<List<PrivateMessage>>.empty();
    }
  }

  /// Uploads an image for a private-chat message. Reuses the same
  /// CloudinaryUploadService as league/organizer/global chat — no new
  /// upload path is introduced. Scoped by threadId so images from
  /// different conversations land in separate Cloudinary folders.
  Future<String> uploadImage({
    required String threadId,
    required PlatformFile file,
  }) {
    return _cloudinary.uploadChatImage(
      file: file,
      folder: 'eleaguehub/chatrooms/private/$threadId',
    );
  }

  /// Uploads a voice note for a private-chat message. Mirrors
  /// ChatRepository.uploadLeagueChatVoice's folder convention.
  Future<String> uploadVoice({
    required String threadId,
    required PlatformFile file,
  }) {
    return _cloudinary.uploadChatVoice(
      file: file,
      folder: 'chat_voice_messages/private/$threadId',
    );
  }

  /// Sends a message. No plan check here — once a thread exists, both
  /// participants (premium or free) can reply. Rules enforce that the
  /// sender must be a participant.
  Future<void> sendTextMessage({
    required String threadId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (trimmed.length > 4000) {
      throw const PrivateChatException('Message is too long.');
    }

    try {
      final authUid = _requireAuthUid();
      final now = DateTime.now().millisecondsSinceEpoch;

      final threadRef = _threads.doc(threadId);
      final msgRef = threadRef.collection('messages').doc();

      final batch = _firestore.batch();
      batch.set(msgRef, <String, dynamic>{
        'senderId': authUid,
        'type': 'text',
        'text': trimmed,
        'imageUrl': '',
        'voiceUrl': '',
        'createdAtMs': now,
      });

      batch.set(
        threadRef,
        <String, dynamic>{
          'lastMessage': trimmed,
          'lastMessageAtMs': now,
          'lastSenderId': authUid,
        },
        SetOptions(merge: true),
      );

      await batch.commit().timeout(const Duration(seconds: 15));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> sendImageMessage({
    required String threadId,
    required String imageUrl,
  }) async {
    final url = imageUrl.trim();
    if (url.isEmpty) return;

    try {
      final authUid = _requireAuthUid();
      final now = DateTime.now().millisecondsSinceEpoch;

      final threadRef = _threads.doc(threadId);
      final msgRef = threadRef.collection('messages').doc();

      final batch = _firestore.batch();
      batch.set(msgRef, <String, dynamic>{
        'senderId': authUid,
        'type': 'image',
        'text': '',
        'imageUrl': url,
        'voiceUrl': '',
        'createdAtMs': now,
      });

      batch.set(
        threadRef,
        <String, dynamic>{
          'lastMessage': '📷 Photo',
          'lastMessageAtMs': now,
          'lastSenderId': authUid,
        },
        SetOptions(merge: true),
      );

      await batch.commit().timeout(const Duration(seconds: 15));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// NEW: sends a voice-note message. Mirrors sendImageMessage exactly —
  /// same batch pattern, same thread-preview update — just with `type:
  /// 'voice'` and `voiceUrl` populated instead of `imageUrl`. The
  /// Firestore rule for `private_threads/{id}/messages` already accepts
  /// `type in ['text','image','voice']`, so no rules change is required.
  Future<void> sendVoiceMessage({
    required String threadId,
    required String voiceUrl,
  }) async {
    final url = voiceUrl.trim();
    if (url.isEmpty) return;

    try {
      final authUid = _requireAuthUid();
      final now = DateTime.now().millisecondsSinceEpoch;

      final threadRef = _threads.doc(threadId);
      final msgRef = threadRef.collection('messages').doc();

      final batch = _firestore.batch();
      batch.set(msgRef, <String, dynamic>{
        'senderId': authUid,
        'type': 'voice',
        'text': '',
        'imageUrl': '',
        'voiceUrl': url,
        'createdAtMs': now,
      });

      batch.set(
        threadRef,
        <String, dynamic>{
          'lastMessage': '🎤 Voice message',
          'lastMessageAtMs': now,
          'lastSenderId': authUid,
        },
        SetOptions(merge: true),
      );

      await batch.commit().timeout(const Duration(seconds: 15));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }
}