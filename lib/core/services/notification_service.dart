import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._internal();

  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  final StreamController<String> _tapStream =
      StreamController<String>.broadcast();
  Stream<String> get onNotificationTap => _tapStream.stream;

  static const String _chatChannelId = 'league_chat_channel';
  static const String _annChannelId = 'league_announcements_channel';
  static const String _testChannelId = 'test_channel_id';
  static const String _organizerFeedChannelId = 'organizer_feed_channel';

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    final dyn = _plugin as dynamic;
    bool ok = false;

    try {
      await dyn.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse resp) {
          final payload = (resp.payload ?? '').trim();
          if (payload.isNotEmpty) _tapStream.add(payload);
        },
      );
      ok = true;
    } catch (_) {}

    if (!ok) {
      try {
        await dyn.initialize(
          initSettings,
          onSelectNotification: (String? payload) {
            final p = (payload ?? '').trim();
            if (p.isNotEmpty) _tapStream.add(p);
          },
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('NotificationService init failed: $e');
        }
      }
    }

    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      try {
        await android.requestNotificationsPermission();
      } catch (_) {}

      try {
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            _chatChannelId,
            'League Chat',
            description: 'Messages from league chatrooms',
            importance: Importance.high,
          ),
        );
      } catch (_) {}

      try {
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            _annChannelId,
            'League Announcements',
            description: 'Announcements from league admins',
            importance: Importance.high,
          ),
        );
      } catch (_) {}

      try {
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            _organizerFeedChannelId,
            'Organizer Feed',
            description: 'Updates from organizers you follow',
            importance: Importance.high,
          ),
        );
      } catch (_) {}

      try {
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            _testChannelId,
            'Test Notifications',
            description: 'Channel for test notifications',
            importance: Importance.high,
          ),
        );
      } catch (_) {}
    }

    _initialized = true;
  }

  int _stableIdFromString(String s) {
    final h = s.hashCode;
    return h < 0 ? -h : h;
  }

  Future<void> showTestNotification() async {
    if (!_initialized) {
      await init();
    }

    const androidDetails = AndroidNotificationDetails(
      _testChannelId,
      'Test Notifications',
      channelDescription: 'Channel for test notifications',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      0,
      'Notifications enabled',
      'You will now receive EleagueHub notifications.',
      details,
    );
  }

  Future<void> showLeagueAnnouncementNotification({
    required String leagueName,
    required String title,
    required String message,
    String? payloadRoute,
  }) async {
    if (!_initialized) {
      await init();
    }

    const androidDetails = AndroidNotificationDetails(
      _annChannelId,
      'League Announcements',
      channelDescription: 'Announcements from league admins',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    final notifTitle = '$leagueName: $title';

    await _plugin.show(
      1,
      notifTitle,
      message,
      details,
      payload: (payloadRoute ?? '').trim().isEmpty ? null : payloadRoute!.trim(),
    );
  }

  Future<void> showOrganizerFeedNotification({
    required int notificationId,
    required String title,
    required String message,
    String? payloadRoute,
  }) async {
    if (!_initialized) {
      await init();
    }

    const androidDetails = AndroidNotificationDetails(
      _organizerFeedChannelId,
      'Organizer Feed',
      channelDescription: 'Updates from organizers you follow',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      notificationId,
      title,
      message,
      details,
      payload: (payloadRoute ?? '').trim().isEmpty ? null : payloadRoute!.trim(),
    );
  }

  Future<void> showLeagueChatMessageNotification({
    required String leagueId,
    required String leagueName,
    required String senderName,
    required String messagePreview,
    String? messageId,
    String? payloadRoute,
  }) async {
    if (!_initialized) {
      await init();
    }

    final title = leagueName.trim().isEmpty ? 'League Chat' : leagueName.trim();
    final bodySender = senderName.trim().isEmpty ? 'Someone' : senderName.trim();
    final bodyMsg =
        messagePreview.trim().isEmpty ? 'New message' : messagePreview.trim();
    final body = '$bodySender: $bodyMsg';

    final androidDetails = AndroidNotificationDetails(
      _chatChannelId,
      'League Chat',
      channelDescription: 'Messages from league chatrooms',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      ticker: 'New message',
      styleInformation: BigTextStyleInformation(body),
      groupKey: 'league_chat_${leagueId.trim()}',
    );

    final details = NotificationDetails(android: androidDetails);

    final id = _stableIdFromString(
      messageId?.trim().isNotEmpty == true
          ? messageId!.trim()
          : '${leagueId}_${DateTime.now().millisecondsSinceEpoch}',
    );

    await _plugin.show(
      id,
      title,
      body,
      details,
      payload: (payloadRoute ?? '').trim().isEmpty ? null : payloadRoute!.trim(),
    );
  }
}
