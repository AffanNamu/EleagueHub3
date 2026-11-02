//chat/data/private_chat_repository.dart
import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../auth/data/user_profile_repository.dart';
import '../../marketplace/data/cloudinary_upload_service.dart';
import '../../profile/data/team_profile_repository.dart';
import '../models/private_message.dart';
import '../models/private_thread.dart';

enum PrivateChatAccess {
  /// A thread already exists — either side can open/reply freely.
  threadExists,
  /// No thread yet, but the viewer has a resolvable profile with any
  /// active plan (free Basic included) and can start one.
  canStart,
  /// No thread yet, and the viewer's profile couldn't be resolved at
  /// all (e.g. not signed in, or an incomplete/missing profile) — not a
  /// plan restriction. See requesterCanStartPrivateChat() in
  /// firestore.rules.
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

  /// Public message-doc ref, exposed so UI can build a ReactionsRepository
  /// (lib/core/reactions/) against the right message.
  DocumentReference<Map<String, dynamic>> messageRef(String threadId, String messageId) {
    return _threads.doc(threadId).collection('messages').doc(messageId);
  }

  /// A fresh Firestore-style id for a not-yet-written message, so the UI
  /// can show an optimistic bubble under the exact id the write (via
  /// [sendTextMessage]'s `messageIdOverride`) will later confirm.
  String newMessageId(String threadId) =>
      _threads.doc(threadId).collection('messages').doc().id;

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
            "You don't have permission to do that right now. Please try again.",
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

      // Starting a chat isn't plan-gated at all -- any signed-in user with
      // a resolvable profile can. (hasPlanActive is NOT what "free" means
      // here: createIfMissing() writes activePlanId as an empty string
      // for a brand-new account, never 'basic', so hasPlanActive is false
      // for every user who hasn't purchased anything -- using it here
      // would re-lock exactly the free users this is meant to allow.)
      final profile = await _userProfiles.fetchByUserId(authUid);
      final canStart = profile != null;

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
  /// Any signed-in user with a resolvable profile can start a new
  /// thread -- not plan-gated at all. This is
  /// enforced both here (fast, friendly error) and in Firestore rules'
  /// requesterCanStartPrivateChat() (authoritative). Once a thread
  /// exists, either participant can reply regardless of their own plan
  /// status. Sending a FILE attachment inside a thread is the one
  /// action that still requires an actual paid plan — see
  /// PrivateChatScreen's image-pick flow and firestore.rules' messages
  /// create rule.
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

      // The initiator just needs a resolvable profile -- not an active
      // plan (see requesterCanStartPrivateChat() in firestore.rules).
      // hasPlanActive is false for every free user who's never purchased
      // anything (createIfMissing() writes activePlanId as '', not
      // 'basic'), so checking it here would wrongly re-lock free users.
      final profile = await _userProfiles.fetchByUserId(authUid);
      final canStart = profile != null;

      if (!canStart) {
        throw const PrivateChatException(
          'Please finish setting up your profile before starting a chat.',
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
          .transform(
            StreamTransformer<List<PrivateThread>, List<PrivateThread>>.fromHandlers(
              handleError: (error, stackTrace, sink) {
                if (kDebugMode) {
                  debugPrint(
                    '[PrivateChatRepository] watchInbox error: $error\n'
                    'If this says "requires an index" / "failed-precondition", '
                    'this query (participantIds arrayContains + orderBy '
                    'lastMessageAtMs) needs a Firestore composite index — '
                    'Firestore usually prints a direct console link right '
                    'after this message; open it to create the index.',
                  );
                }
                // Forward the error — do NOT fake an empty list here. A
                // real thread that fails to load must show as an error in
                // the UI, never as "no conversations", or existing chats
                // appear to silently vanish.
                sink.addError(error, stackTrace);
              },
            ),
          );
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
          .transform(
            StreamTransformer<List<PrivateMessage>, List<PrivateMessage>>.fromHandlers(
              handleError: (error, stackTrace, sink) {
                if (kDebugMode) {
                  debugPrint('[PrivateChatRepository] watchMessages error: $error');
                }
                sink.addError(error, stackTrace);
              },
            ),
          );
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

  /// Sends a message. No plan check and no daily cap here — once a thread
  /// exists, both participants (premium or free) can send text/voice
  /// messages freely. Rules enforce that the sender must be a participant
  /// (and that only an image attachment is paid-gated, in the messages
  /// create rule).
  /// Returns the sent message's id (used by the caller to also trigger a
  /// push notification via SupabaseEdgeNotificationsService).
  Future<String> sendTextMessage({
    required String threadId,
    required String text,
    String messageIdOverride = '',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length > 4000) {
      throw const PrivateChatException('Message is too long.');
    }

    try {
      final authUid = _requireAuthUid();
      final now = DateTime.now().millisecondsSinceEpoch;

      final threadRef = _threads.doc(threadId);
      final overrideId = messageIdOverride.trim();
      final msgRef = overrideId.isNotEmpty
          ? threadRef.collection('messages').doc(overrideId)
          : threadRef.collection('messages').doc();

      final messageData = <String, dynamic>{
        'senderId': authUid,
        'type': 'text',
        'text': trimmed,
        'imageUrl': '',
        'voiceUrl': '',
        'createdAtMs': now,
      };
      final threadUpdate = <String, dynamic>{
        'lastMessage': trimmed,
        'lastMessageAtMs': now,
        'lastSenderId': authUid,
      };

      final batch = _firestore.batch();
      batch.set(msgRef, messageData);
      batch.set(threadRef, threadUpdate, SetOptions(merge: true));
      await batch.commit().timeout(const Duration(seconds: 15));
      return msgRef.id;
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Returns the sent message's id.
  Future<String> sendImageMessage({
    required String threadId,
    required String imageUrl,
  }) async {
    final url = imageUrl.trim();
    if (url.isEmpty) return '';

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
      return msgRef.id;
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Sends a voice-note message. Same shape as sendTextMessage — a direct
  /// batch write, no plan check and no daily cap (private chat text/voice
  /// is free for everyone; only an image attachment is paid-gated).
  ///
  /// Returns the sent message's id.
  Future<String> sendVoiceMessage({
    required String threadId,
    required String voiceUrl,
    int voiceDurationMs = 0,
  }) async {
    final url = voiceUrl.trim();
    if (url.isEmpty) return '';

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
        'voiceDurationMs': voiceDurationMs < 0 ? 0 : voiceDurationMs,
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
      return msgRef.id;
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }
}