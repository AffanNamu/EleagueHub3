import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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
  static const String _organizerChatChannelId = 'organizer_chat_channel';
  static const String _globalChatChannelId = 'global_chat_channel';
  static const String _privateChatChannelId = 'private_chat_channel';
  static const String _annChannelId = 'league_announcements_channel';
  static const String _testChannelId = 'test_channel_id';
  static const String _organizerFeedChannelId = 'organizer_feed_channel';
  static const String _newFollowerChannelId = 'new_follower_channel';

  /// Call this ONLY when user explicitly enables notifications in settings
  /// or when user first interacts with a feature that needs notifications.
  /// Do NOT call at app startup.
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
      // ─────────────────────────────────────────────────────────────────────
      // REMOVED: requestNotificationsPermission() from here.
      // Permission is now requested lazily via requestPermissionIfNeeded()
      // which is called ONLY when user turns on notifications in settings.
      // ─────────────────────────────────────────────────────────────────────

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
            _organizerChatChannelId,
            'Organizer Chat',
            description: 'Messages from organizer workspace chatrooms',
            importance: Importance.high,
          ),
        );
      } catch (_) {}

      try {
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            _globalChatChannelId,
            'Global Chat',
            description: 'Messages from the global chatroom',
            importance: Importance.high,
          ),
        );
      } catch (_) {}

      try {
        await android.createNotificationChannel(
          const AndroidNotificationChannel(
            _privateChatChannelId,
            'Private Messages',
            description: 'Direct messages from other users',
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
            _newFollowerChannelId,
            'New Followers',
            description: 'Someone started following you',
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

  /// Call this ONLY when user explicitly wants notifications
  /// (e.g. toggling notifications ON in your settings screen).
  /// Returns true if permission was granted.
  Future<bool> requestPermissionIfNeeded() async {
    // Make sure plugin is initialized first (channels etc.)
    await init();

    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (android == null) return false;

    try {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    } catch (_) {
      return false;
    }
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
      payload:
          (payloadRoute ?? '').trim().isEmpty ? null : payloadRoute!.trim(),
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
      payload:
          (payloadRoute ?? '').trim().isEmpty ? null : payloadRoute!.trim(),
    );
  }

  /// Downloads a remote image to a local temp file for use with Android's
  /// BigPictureStyleInformation, which requires a local file path (not a
  /// URL). Returns null on any failure so callers can gracefully fall back
  /// to a text-only notification instead of losing the notification
  /// entirely over a bad/unreachable image URL.
  Future<String?> _downloadToLocalFile(String url, String cacheKey) async {
    final u = url.trim();
    if (u.isEmpty) return null;

    try {
      final dir = await getTemporaryDirectory();
      final ext = u.contains('.png') ? 'png' : 'jpg';
      final file = File('${dir.path}/notif_$cacheKey.$ext');

      final resp = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 8));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;

      await file.writeAsBytes(resp.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> showNewFollowerNotification({
    required int notificationId,
    required String actorName,
    String? actorAvatarUrl,
    String? payloadRoute,
  }) async {
    if (!_initialized) {
      await init();
    }

    final name = actorName.trim().isEmpty ? 'Someone' : actorName.trim();
    final body = '$name started following you.';

    final localImagePath = actorAvatarUrl == null
        ? null
        : await _downloadToLocalFile(actorAvatarUrl, 'follow_$notificationId');

    final androidDetails = AndroidNotificationDetails(
      _newFollowerChannelId,
      'New Followers',
      channelDescription: 'Someone started following you',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: localImagePath != null
          ? BigPictureStyleInformation(
              FilePathAndroidBitmap(localImagePath),
              largeIcon: FilePathAndroidBitmap(localImagePath),
              contentTitle: 'New follower',
              summaryText: body,
            )
          : const BigTextStyleInformation(''),
      largeIcon:
          localImagePath != null ? FilePathAndroidBitmap(localImagePath) : null,
    );

    final details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      notificationId,
      'New follower',
      body,
      details,
      payload:
          (payloadRoute ?? '').trim().isEmpty ? null : payloadRoute!.trim(),
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

    final title =
        leagueName.trim().isEmpty ? 'League Chat' : leagueName.trim();
    final bodySender =
        senderName.trim().isEmpty ? 'Someone' : senderName.trim();
    final bodyMsg = messagePreview.trim().isEmpty
        ? 'New message'
        : messagePreview.trim();
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
      payload:
          (payloadRoute ?? '').trim().isEmpty ? null : payloadRoute!.trim(),
    );
  }

  Future<void> showPrivateMessageNotification({
    required String threadId,
    required String senderName,
    required String messagePreview,
    String? messageId,
    String? payloadRoute,
  }) async {
    if (!_initialized) {
      await init();
    }

    final title = senderName.trim().isEmpty ? 'New Message' : senderName.trim();
    final body = messagePreview.trim().isEmpty ? 'New message' : messagePreview.trim();

    final androidDetails = AndroidNotificationDetails(
      _privateChatChannelId,
      'Private Messages',
      channelDescription: 'Direct messages from other users',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      ticker: 'New message',
      styleInformation: BigTextStyleInformation(body),
      groupKey: 'private_chat_${threadId.trim()}',
    );

    final details = NotificationDetails(android: androidDetails);

    final id = _stableIdFromString(
      messageId?.trim().isNotEmpty == true
          ? messageId!.trim()
          : '${threadId}_${DateTime.now().millisecondsSinceEpoch}',
    );

    await _plugin.show(
      id,
      title,
      body,
      details,
      payload:
          (payloadRoute ?? '').trim().isEmpty ? null : payloadRoute!.trim(),
    );
  }
}
