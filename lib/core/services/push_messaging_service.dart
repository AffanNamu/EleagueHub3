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

  /// Used to suppress WhatsApp-style foreground banners when user is already inside that league chat.
  final ValueNotifier<String?> activeLeagueChatId = ValueNotifier<String?>(null);

  void setActiveLeagueChat(String? leagueId) {
    final v = (leagueId ?? '').trim();
    activeLeagueChatId.value = v.isEmpty ? null : v;
  }

  String _leagueTopic(String leagueId) => 'league_${leagueId.trim()}';
  String _muteTopic(String uid, String leagueId) =>
      'mute_${uid.trim()}_${leagueId.trim()}';

  Future<void> subscribeToLeagueTopic(String leagueId) async {
    final id = leagueId.trim();
    if (id.isEmpty) return;

    try {
      await _messaging.subscribeToTopic(_leagueTopic(id));
    } catch (_) {}

    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isNotEmpty) {
      try {
        await _messaging.subscribeToTopic(_muteTopic(uid, id));
      } catch (_) {}
    }
  }

  Future<void> unsubscribeFromLeagueTopic(String leagueId) async {
    final id = leagueId.trim();
    if (id.isEmpty) return;

    try {
      await _messaging.unsubscribeFromTopic(_leagueTopic(id));
    } catch (_) {}

    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isNotEmpty) {
      try {
        await _messaging.unsubscribeFromTopic(_muteTopic(uid, id));
      } catch (_) {}
    }
  }

  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    try {
      await _messaging.setAutoInitEnabled(true);
    } catch (_) {}

    try {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (_) {}

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

      final type = (data['type'] ?? '').toString().trim();
      final leagueId = (data['leagueId'] ?? '').toString().trim();
      final senderId = (data['senderId'] ?? '').toString().trim();

      if (leagueId.isNotEmpty && activeLeagueChatId.value?.trim() == leagueId) {
        return;
      }

      final myUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      if (myUid.isNotEmpty && senderId.isNotEmpty && myUid == senderId) return;

      if (type == 'league_chat' ||
          (leagueId.isNotEmpty &&
              (data['route'] ?? '').toString().trim().isNotEmpty)) {
        final leagueName =
            (data['leagueName'] ?? m.notification?.title ?? 'League')
                .toString()
                .trim();
        final senderName = (data['senderName'] ?? '').toString().trim();
        final preview =
            (data['preview'] ?? m.notification?.body ?? 'New message')
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
      }
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
