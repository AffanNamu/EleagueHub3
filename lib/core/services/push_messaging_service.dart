import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../routing/app_router.dart';
import 'followed_organizer_notifications_service.dart';
import 'notification_service.dart';

class PushMessagingService {
  PushMessagingService._();

  static final PushMessagingService instance = PushMessagingService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenedSub;

  bool _inited = false;

  /// Used to suppress foreground banners when user is already inside that league chat.
  final ValueNotifier<String?> activeLeagueChatId = ValueNotifier<String?>(null);

  /// Used to suppress foreground banners when user is already inside that
  /// private chat thread.
  final ValueNotifier<String?> activeThreadId = ValueNotifier<String?>(null);

  void setActiveLeagueChat(String? leagueId) {
    final v = (leagueId ?? '').trim();
    activeLeagueChatId.value = v.isEmpty ? null : v;
  }

  void setActiveThread(String? threadId) {
    final v = (threadId ?? '').trim();
    activeThreadId.value = v.isEmpty ? null : v;
  }

  // Same topic-pair scheme used for every "room" type (league, organizer
  // workspace, global chat): 'league_{key}' for the room broadcast and
  // 'mute_{uid}_{key}' so a device can be excluded (e.g. the sender, or
  // someone who muted that room) via an FCM condition on the sender side.
  // The key just needs to be unique per room; organizer/global chat use
  // a namespaced key ('organizer_{id}', 'global') so they can never
  // collide with a real league id.
  static int _stableIdFromString(String s) {
    final h = s.hashCode;
    return h < 0 ? -h : h;
  }

  /// Builds and shows the right local notification for an incoming FCM
  /// `data` payload. Shared between the foreground [FirebaseMessaging.onMessage]
  /// listener above and `firebaseMessagingBackgroundHandler` in main.dart,
  /// which runs in a separate headless isolate when the app is backgrounded
  /// or terminated -- both are needed since every chat-notify payload is now
  /// data-only (see the Supabase edge functions' notes on this), so the OS
  /// never auto-renders anything on its own.
  static Future<void> showLocalNotificationForData(
    Map<String, dynamic> data, {
    RemoteNotification? notification,
  }) async {
    final type = (data['type'] ?? '').toString().trim();
    final leagueId = (data['leagueId'] ?? '').toString().trim();
    final senderId = (data['senderId'] ?? '').toString().trim();

    if (type == 'league_chat' ||
        (type.isEmpty &&
            leagueId.isNotEmpty &&
            (data['route'] ?? '').toString().trim().isNotEmpty)) {
      final leagueName =
          (data['leagueName'] ?? notification?.title ?? 'League')
              .toString()
              .trim();
      final senderName = (data['senderName'] ?? '').toString().trim();
      final preview =
          (data['preview'] ?? notification?.body ?? 'New message')
              .toString()
              .trim();
      final messageId = (data['messageId'] ?? '').toString().trim();
      final route = (data['route'] ?? '').toString().trim();

      try {
        await NotificationService().showLeagueChatMessageNotification(
          leagueId: leagueId.isNotEmpty ? leagueId : 'league',
          leagueName: leagueName.isNotEmpty ? leagueName : 'League',
          senderName: senderName.isNotEmpty ? senderName : 'Someone',
          messagePreview: preview.isNotEmpty ? preview : 'New message',
          messageId: messageId.isNotEmpty ? messageId : null,
          payloadRoute: route.isNotEmpty ? route : null,
        );
      } catch (_) {}
    } else if (type == 'private_message') {
      final threadId = (data['threadId'] ?? '').toString().trim();
      final senderName = (data['senderName'] ?? '').toString().trim();
      final preview =
          (data['preview'] ?? notification?.body ?? 'New message')
              .toString()
              .trim();
      final messageId = (data['messageId'] ?? '').toString().trim();
      final route = (data['route'] ?? '').toString().trim();

      try {
        await NotificationService().showPrivateMessageNotification(
          threadId: threadId.isNotEmpty ? threadId : 'thread',
          senderId: senderId,
          senderName: senderName.isNotEmpty ? senderName : 'Someone',
          messagePreview: preview.isNotEmpty ? preview : 'New message',
          messageId: messageId.isNotEmpty ? messageId : null,
          payloadRoute: route.isNotEmpty ? route : null,
        );
      } catch (_) {}
    } else if (type == 'organizer_chat') {
      final masterLeagueId = (data['masterLeagueId'] ?? '').toString().trim();
      final workspaceName =
          (data['leagueName'] ?? notification?.title ?? 'Organizer Chat')
              .toString()
              .trim();
      final senderName = (data['senderName'] ?? '').toString().trim();
      final preview =
          (data['preview'] ?? notification?.body ?? 'New message')
              .toString()
              .trim();
      final messageId = (data['messageId'] ?? '').toString().trim();
      final route = (data['route'] ?? '').toString().trim();

      try {
        await NotificationService().showOrganizerChatMessageNotification(
          masterLeagueId: masterLeagueId.isNotEmpty ? masterLeagueId : 'organizer',
          workspaceName: workspaceName.isNotEmpty ? workspaceName : 'Organizer Chat',
          senderName: senderName.isNotEmpty ? senderName : 'Someone',
          messagePreview: preview.isNotEmpty ? preview : 'New message',
          messageId: messageId.isNotEmpty ? messageId : null,
          payloadRoute: route.isNotEmpty ? route : null,
        );
      } catch (_) {}
    } else if (type == 'global_chat') {
      final senderName = (data['senderName'] ?? '').toString().trim();
      final preview =
          (data['preview'] ?? notification?.body ?? 'New message')
              .toString()
              .trim();
      final messageId = (data['messageId'] ?? '').toString().trim();
      final route = (data['route'] ?? '').toString().trim();

      try {
        await NotificationService().showGlobalChatMessageNotification(
          senderName: senderName.isNotEmpty ? senderName : 'Someone',
          messagePreview: preview.isNotEmpty ? preview : 'New message',
          messageId: messageId.isNotEmpty ? messageId : null,
          payloadRoute: route.isNotEmpty ? route : null,
        );
      } catch (_) {}
    } else if (type == 'new_follower') {
      final actorId = (data['actorId'] ?? '').toString().trim();
      final actorName = (data['actorName'] ?? 'Someone').toString().trim();
      final route = (data['route'] ?? '').toString().trim();

      try {
        await NotificationService().showNewFollowerNotification(
          notificationId: _stableIdFromString(
            actorId.isNotEmpty
                ? actorId
                : 'anon_${DateTime.now().millisecondsSinceEpoch}',
          ),
          actorName: actorName.isNotEmpty ? actorName : 'Someone',
          payloadRoute: route.isNotEmpty ? route : null,
        );
      } catch (_) {}
    } else if (type == 'organizer_announcement') {
      final actorId = (data['actorId'] ?? '').toString().trim();
      final actorName = (data['actorName'] ?? 'An organizer').toString().trim();
      final route = (data['route'] ?? '').toString().trim();
      final title = (notification?.title ?? actorName).toString().trim();
      final body =
          (notification?.body ?? 'Posted an update.').toString().trim();

      try {
        await NotificationService().showOrganizerFeedNotification(
          notificationId: _stableIdFromString(
            '${actorId}_${DateTime.now().millisecondsSinceEpoch}',
          ),
          title: title.isNotEmpty ? title : actorName,
          message: body.isNotEmpty ? body : 'Posted an update.',
          payloadRoute: route.isNotEmpty ? route : null,
        );
      } catch (_) {}
    } else if (type.startsWith('football_')) {
      // football_goal / football_kickoff / football_fulltime, sent by the
      // Worker's live-score poller (_pollLiveFixturesAndNotify). Title/body
      // come straight from the FCM `notification` block the Worker sends
      // (same as organizer_announcement above), since the Worker already
      // built the right copy per event kind.
      final fixtureId = (data['fixtureId'] ?? '').toString().trim();
      final route = (data['route'] ?? '').toString().trim();
      final title = (notification?.title ?? 'Football Hub').toString().trim();
      final body = (notification?.body ?? '').toString().trim();

      try {
        await NotificationService().showFootballEventNotification(
          notificationId: _stableIdFromString(
            '${type}_${fixtureId}_${DateTime.now().millisecondsSinceEpoch}',
          ),
          title: title.isNotEmpty ? title : 'Football Hub',
          message: body.isNotEmpty ? body : 'Match update.',
          payloadRoute: route.isNotEmpty ? route : null,
        );
      } catch (_) {}
    }
  }

  String _leagueTopic(String key) => 'league_${key.trim()}';
  String _muteTopic(String uid, String key) =>
      'mute_${uid.trim()}_${key.trim()}';

  Future<void> _subscribeTopicPair(String key) async {
    final k = key.trim();
    if (k.isEmpty) return;

    try {
      await _messaging.subscribeToTopic(_leagueTopic(k));
    } catch (_) {}

    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isNotEmpty) {
      try {
        await _messaging.subscribeToTopic(_muteTopic(uid, k));
      } catch (_) {}
    }
  }

  Future<void> _unsubscribeTopicPair(String key) async {
    final k = key.trim();
    if (k.isEmpty) return;

    try {
      await _messaging.unsubscribeFromTopic(_leagueTopic(k));
    } catch (_) {}

    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isNotEmpty) {
      try {
        await _messaging.unsubscribeFromTopic(_muteTopic(uid, k));
      } catch (_) {}
    }
  }

  Future<void> subscribeToLeagueTopic(String leagueId) =>
      _subscribeTopicPair(leagueId);

  Future<void> unsubscribeFromLeagueTopic(String leagueId) =>
      _unsubscribeTopicPair(leagueId);

  Future<void> subscribeToOrganizerChatTopic(String masterLeagueId) =>
      _subscribeTopicPair('organizer_${masterLeagueId.trim()}');

  Future<void> unsubscribeFromOrganizerChatTopic(String masterLeagueId) =>
      _unsubscribeTopicPair('organizer_${masterLeagueId.trim()}');

  Future<void> subscribeToGlobalChatTopic() => _subscribeTopicPair('global');

  Future<void> unsubscribeFromGlobalChatTopic() =>
      _unsubscribeTopicPair('global');

  /// Sets up message listeners and token syncing.
  /// Does NOT ask for notification permission — that is done lazily
  /// via [requestNotificationPermission] when user enables notifications.
  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    try {
      await _messaging.setAutoInitEnabled(true);
    } catch (_) {}

    // ─────────────────────────────────────────────────────────────────────
    // REMOVED: requestPermission() from here.
    // Permission is now only requested when user explicitly enables
    // notifications in the settings screen via requestNotificationPermission().
    // ─────────────────────────────────────────────────────────────────────

    try {
      await FollowedOrganizerNotificationsService.instance.init();
    } catch (_) {}

    _onOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((m) {
      final route = (m.data['route'] ?? '').toString().trim();
      if (route.isEmpty || !route.startsWith('/')) return;
      appRouter.go(route);
    });

    try {
      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        final route = (initial.data['route'] ?? '').toString().trim();
        if (route.isNotEmpty && route.startsWith('/')) {
          scheduleMicrotask(() => appRouter.go(route));
        }
      }
    } catch (_) {}

    _onMessageSub = FirebaseMessaging.onMessage.listen((m) async {
      final data = m.data;

      final leagueId = (data['leagueId'] ?? '').toString().trim();
      final senderId = (data['senderId'] ?? '').toString().trim();
      final threadId = (data['threadId'] ?? '').toString().trim();

      if (leagueId.isNotEmpty &&
          activeLeagueChatId.value?.trim() == leagueId) {
        return;
      }
      if (threadId.isNotEmpty && activeThreadId.value?.trim() == threadId) {
        return;
      }

      final myUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      if (myUid.isNotEmpty && senderId.isNotEmpty && myUid == senderId) return;

      await PushMessagingService.showLocalNotificationForData(
        data,
        notification: m.notification,
      );
    });

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      _tokenSub?.cancel();
      _tokenSub = null;

      if (user == null) return;

      await _syncTokenToFirestore(user.uid);

      _tokenSub = _messaging.onTokenRefresh.listen((t) {
        final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
        if (uid.isEmpty) return;
        _syncSpecificTokenToFirestore(uid: uid, token: t);
      });
    });
  }

  /// Call this ONLY when user explicitly enables notifications
  /// (e.g. toggling the notifications switch in your settings screen).
  /// Returns true if permission was granted.
  Future<bool> requestNotificationPermission() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      if (granted) {
        // Also request local notification permission on Android 13+
        await NotificationService().requestPermissionIfNeeded();
      }

      return granted;
    } catch (_) {
      return false;
    }
  }

  Future<void> _syncTokenToFirestore(String uid) async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.trim().isEmpty) return;
      await _syncSpecificTokenToFirestore(uid: uid, token: token);
    } catch (_) {}
  }

  Future<void> _syncSpecificTokenToFirestore({
    required String uid,
    required String token,
  }) async {
    final u = uid.trim();
    final t = token.trim();
    if (u.isEmpty || t.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(u)
          .collection('fcmTokens')
          .doc(t)
          .set(
        <String, dynamic>{
          'token': t,
          'platform': defaultTargetPlatform.name,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  void dispose() {
    _authSub?.cancel();
    _tokenSub?.cancel();
    _onMessageSub?.cancel();
    _onOpenedSub?.cancel();
    FollowedOrganizerNotificationsService.instance.dispose();
  }
}
