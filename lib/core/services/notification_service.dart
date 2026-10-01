import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../firebase_options.dart';
import 'notification_reply_handler.dart';

/// Action id for the inline "Reply" button (Android RemoteInput) attached to
/// chat notifications, letting a user answer directly from the notification
/// shade without opening the app. Must be a top-level const (not a class
/// member) since the background response handler below is a standalone
/// entry-point function running in its own isolate.
const String kReplyNotificationActionId = 'reply_action';

/// Registered as `onDidReceiveBackgroundNotificationResponse`. Runs in a
/// separate headless isolate when the notification is acted on while the
/// app is backgrounded/terminated -- must stay synchronous (`void`, not
/// `Future<void>`), so any real work is fired off without awaiting here.
@pragma('vm:entry-point')
void notificationBackgroundResponseHandler(NotificationResponse response) {
  if (response.actionId != kReplyNotificationActionId) return;

  final replyText = (response.input ?? '').trim();
  if (replyText.isEmpty) return;

  final payload = (response.payload ?? '').trim();
  if (payload.isEmpty || !payload.startsWith('{')) return;

  Map<String, dynamic>? data;
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map) data = Map<String, dynamic>.from(decoded);
  } catch (_) {
    return;
  }
  if (data == null) return;

  unawaited(_replyInBackgroundIsolate(data, replyText));
}

Future<void> _replyInBackgroundIsolate(
  Map<String, dynamic> data,
  String replyText,
) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {}

  await NotificationReplyHandler.handle(data, replyText);
}

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
  static const String _footballHubChannelId = 'football_hub_channel';

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
        onDidReceiveNotificationResponse: _handleForegroundResponse,
        onDidReceiveBackgroundNotificationResponse:
            notificationBackgroundResponseHandler,
      );
      ok = true;
    } catch (_) {}

    if (!ok) {
      try {
        await dyn.initialize(
          initSettings,
          onDidReceiveNotificationResponse: _handleForegroundResponse,
        );
        ok = true;
      } catch (_) {}
    }

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
            _footballHubChannelId,
            'Football Hub',
            description: 'Goals and match updates for teams you follow',
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

  /// Handles a tap or an inline Reply submission while the app is in the
  /// foreground. A background tap/reply is handled separately by the
  /// top-level [notificationBackgroundResponseHandler] entry-point, which
  /// runs in its own isolate and has no access to this instance.
  void _handleForegroundResponse(NotificationResponse resp) {
    final payload = (resp.payload ?? '').trim();
    if (payload.isEmpty) return;

    if (resp.actionId == kReplyNotificationActionId) {
      final replyText = (resp.input ?? '').trim();
      if (replyText.isEmpty) return;
      final data = _decodeChatPayload(payload);
      if (data == null) return;
      NotificationReplyHandler.handle(data, replyText);
      return;
    }

    final route = _routeFromPayload(payload);
    if (route.isNotEmpty) _tapStream.add(route);
  }

  Map<String, dynamic>? _decodeChatPayload(String payload) {
    if (!payload.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  /// Older notification types (announcements, new follower, organizer feed,
  /// test) still pass a bare route string as their payload; the four chat
  /// message types pass JSON (needed to carry reply context) with the route
  /// nested under a `route` key.
  String _routeFromPayload(String payload) {
    final data = _decodeChatPayload(payload);
    if (data != null) return (data['route'] ?? '').toString().trim();
    return payload;
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

  Future<void> showFootballEventNotification({
    required int notificationId,
    required String title,
    required String message,
    String? payloadRoute,
  }) async {
    if (!_initialized) {
      await init();
    }

    const androidDetails = AndroidNotificationDetails(
      _footballHubChannelId,
      'Football Hub',
      channelDescription: 'Goals and match updates for teams you follow',
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

  /// Inline reply input shown as a text field under the Reply action.
  /// Android-only -- iOS custom actions with text input would need a native
  /// Notification Content Extension, not added here.
  List<AndroidNotificationAction> get _replyActions => [
        const AndroidNotificationAction(
          kReplyNotificationActionId,
          'Reply',
          allowGeneratedReplies: false,
          inputs: [AndroidNotificationActionInput()],
          cancelNotification: true,
        ),
      ];

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
      actions: _replyActions,
    );

    final details = NotificationDetails(android: androidDetails);

    final id = _stableIdFromString(
      messageId?.trim().isNotEmpty == true
          ? messageId!.trim()
          : '${leagueId}_${DateTime.now().millisecondsSinceEpoch}',
    );

    final route = (payloadRoute ?? '').trim();
    final payload = jsonEncode({
      'type': 'league_chat',
      'route': route,
      'leagueId': leagueId.trim(),
      'leagueName': title,
    });

    await _plugin.show(id, title, body, details, payload: payload);
  }

  Future<void> showOrganizerChatMessageNotification({
    required String masterLeagueId,
    required String workspaceName,
    required String senderName,
    required String messagePreview,
    String? messageId,
    String? payloadRoute,
  }) async {
    if (!_initialized) {
      await init();
    }

    final title =
        workspaceName.trim().isEmpty ? 'Organizer Chat' : workspaceName.trim();
    final bodySender =
        senderName.trim().isEmpty ? 'Someone' : senderName.trim();
    final bodyMsg = messagePreview.trim().isEmpty
        ? 'New message'
        : messagePreview.trim();
    final body = '$bodySender: $bodyMsg';

    final androidDetails = AndroidNotificationDetails(
      _organizerChatChannelId,
      'Organizer Chat',
      channelDescription: 'Messages from organizer workspace chatrooms',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      ticker: 'New message',
      styleInformation: BigTextStyleInformation(body),
      groupKey: 'organizer_chat_${masterLeagueId.trim()}',
      actions: _replyActions,
    );

    final details = NotificationDetails(android: androidDetails);

    final id = _stableIdFromString(
      messageId?.trim().isNotEmpty == true
          ? messageId!.trim()
          : '${masterLeagueId}_${DateTime.now().millisecondsSinceEpoch}',
    );

    final route = (payloadRoute ?? '').trim();
    final payload = jsonEncode({
      'type': 'organizer_chat',
      'route': route,
      'masterLeagueId': masterLeagueId.trim(),
      'leagueName': title,
    });

    await _plugin.show(id, title, body, details, payload: payload);
  }

  Future<void> showGlobalChatMessageNotification({
    required String senderName,
    required String messagePreview,
    String? messageId,
    String? payloadRoute,
  }) async {
    if (!_initialized) {
      await init();
    }

    const title = 'Global Chat';
    final bodySender =
        senderName.trim().isEmpty ? 'Someone' : senderName.trim();
    final bodyMsg = messagePreview.trim().isEmpty
        ? 'New message'
        : messagePreview.trim();
    final body = '$bodySender: $bodyMsg';

    final androidDetails = AndroidNotificationDetails(
      _globalChatChannelId,
      'Global Chat',
      channelDescription: 'Messages from the global chatroom',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      ticker: 'New message',
      styleInformation: BigTextStyleInformation(body),
      groupKey: 'global_chat',
      actions: _replyActions,
    );

    final details = NotificationDetails(android: androidDetails);

    final id = _stableIdFromString(
      messageId?.trim().isNotEmpty == true
          ? messageId!.trim()
          : 'global_${DateTime.now().millisecondsSinceEpoch}',
    );

    final route = (payloadRoute ?? '').trim();
    final payload = jsonEncode({
      'type': 'global_chat',
      'route': route,
    });

    await _plugin.show(id, title, body, details, payload: payload);
  }

  Future<void> showPrivateMessageNotification({
    required String threadId,
    required String senderId,
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
      actions: _replyActions,
    );

    final details = NotificationDetails(android: androidDetails);

    final id = _stableIdFromString(
      messageId?.trim().isNotEmpty == true
          ? messageId!.trim()
          : '${threadId}_${DateTime.now().millisecondsSinceEpoch}',
    );

    final route = (payloadRoute ?? '').trim();
    // `senderId` here is the OTHER party in this thread -- i.e. the
    // recipient of a reply typed from this notification.
    final payload = jsonEncode({
      'type': 'private_message',
      'route': route,
      'threadId': threadId.trim(),
      'senderId': senderId.trim(),
    });

    await _plugin.show(id, title, body, details, payload: payload);
  }
}
