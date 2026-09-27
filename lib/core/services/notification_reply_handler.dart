// lib/core/services/notification_reply_handler.dart
//
// Sends a chat message typed directly into a notification's inline Reply
// action (Android RemoteInput), without opening the app. Called from
// NotificationService's onDidReceiveNotificationResponse (foreground) and
// onDidReceiveBackgroundNotificationResponse (app backgrounded/terminated)
// callbacks -- the latter runs in its own headless Dart isolate, so this
// only touches plain Firestore/HTTP calls, never anything UI-related.
//
// Reuses the exact same repository methods (and therefore the exact same
// free-tier daily rate limit) the normal in-app chat screens use, so a
// notification reply can never bypass RateLimitService's cap.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../features/chat/data/chat_repository.dart';
import '../../features/chat/data/private_chat_repository.dart';
import 'supabase_edge_notifications_service.dart';

class NotificationReplyHandler {
  const NotificationReplyHandler._();

  /// [data] is the decoded JSON payload NotificationService attaches to
  /// each chat notification -- see NotificationService's `_encodePayload`.
  static Future<void> handle(Map<String, dynamic> data, String replyText) async {
    final text = replyText.trim();
    if (text.isEmpty) return;

    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    final type = (data['type'] ?? '').toString().trim();

    try {
      final identity = await _resolveSenderIdentity(uid);

      switch (type) {
        case 'league_chat':
          await _replyToLeagueChat(data, uid, identity, text);
          break;
        case 'organizer_chat':
          await _replyToOrganizerChat(data, uid, identity, text);
          break;
        case 'global_chat':
          await _replyToGlobalChat(uid, identity, text);
          break;
        case 'private_message':
          await _replyToPrivateMessage(data, uid, identity, text);
          break;
        default:
          return;
      }
    } catch (_) {
      // Best-effort: a failed background reply (offline, rate-limited,
      // etc.) just means the message doesn't send -- there is no UI here
      // to surface an error to, and the user can always open the app and
      // retry from the chat itself.
    }
  }

  static Future<(String name, String photo)> _resolveSenderIdentity(
    String uid,
  ) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 8));
      final data = snap.data() ?? const <String, dynamic>{};
      final name = (data['teamName'] as String?)?.trim() ?? '';
      final photo = (data['photoUrl'] as String?)?.trim() ?? '';
      return (name.isEmpty ? 'Player' : name, photo);
    } catch (_) {
      return ('Player', '');
    }
  }

  static Future<void> _replyToLeagueChat(
    Map<String, dynamic> data,
    String uid,
    (String, String) identity,
    String text,
  ) async {
    final leagueId = (data['leagueId'] ?? '').toString().trim();
    if (leagueId.isEmpty) return;
    final leagueName = (data['leagueName'] ?? 'League').toString().trim();

    final repo = ChatRepository();
    final messageId = FirebaseFirestore.instance.collection('_ids').doc().id;

    await repo.sendLeagueMessage(
      leagueId: leagueId,
      senderId: uid,
      senderName: identity.$1,
      senderPhoto: identity.$2,
      type: 'text',
      text: text,
      messageIdOverride: messageId,
    );

    await SupabaseEdgeNotificationsService.instance.notifyLeagueChatMessage(
      leagueId: leagueId,
      leagueName: leagueName,
      messageId: messageId,
      senderId: uid,
      senderName: identity.$1,
      preview: text,
    );
  }

  static Future<void> _replyToOrganizerChat(
    Map<String, dynamic> data,
    String uid,
    (String, String) identity,
    String text,
  ) async {
    final masterLeagueId = (data['masterLeagueId'] ?? '').toString().trim();
    if (masterLeagueId.isEmpty) return;
    final workspaceName = (data['leagueName'] ?? 'Organizer Chat').toString().trim();

    final repo = ChatRepository();
    final messageId = FirebaseFirestore.instance.collection('_ids').doc().id;

    await repo.sendOrganizerMessage(
      masterLeagueId: masterLeagueId,
      senderId: uid,
      senderName: identity.$1,
      senderPhoto: identity.$2,
      type: 'text',
      text: text,
      messageIdOverride: messageId,
    );

    await SupabaseEdgeNotificationsService.instance.notifyOrganizerChatMessage(
      masterLeagueId: masterLeagueId,
      workspaceName: workspaceName,
      messageId: messageId,
      senderId: uid,
      senderName: identity.$1,
      preview: text,
    );
  }

  static Future<void> _replyToGlobalChat(
    String uid,
    (String, String) identity,
    String text,
  ) async {
    final repo = ChatRepository();
    final messageId = FirebaseFirestore.instance.collection('_ids').doc().id;

    await repo.sendGlobalMessage(
      senderId: uid,
      senderName: identity.$1,
      senderPhoto: identity.$2,
      type: 'text',
      text: text,
      messageIdOverride: messageId,
    );

    await SupabaseEdgeNotificationsService.instance.notifyGlobalChatMessage(
      messageId: messageId,
      senderId: uid,
      senderName: identity.$1,
      preview: text,
    );
  }

  static Future<void> _replyToPrivateMessage(
    Map<String, dynamic> data,
    String uid,
    (String, String) identity,
    String text,
  ) async {
    final threadId = (data['threadId'] ?? '').toString().trim();
    if (threadId.isEmpty) return;
    // The original sender of the message being replied to is now the
    // recipient of this reply.
    final recipientId = (data['senderId'] ?? '').toString().trim();
    if (recipientId.isEmpty) return;

    final repo = PrivateChatRepository();
    final messageId = await repo.sendTextMessage(threadId: threadId, text: text);
    if (messageId.isEmpty) return;

    await SupabaseEdgeNotificationsService.instance.notifyPrivateMessage(
      threadId: threadId,
      recipientId: recipientId,
      messageId: messageId,
      senderId: uid,
      senderName: identity.$1,
      preview: text,
    );
  }
}
