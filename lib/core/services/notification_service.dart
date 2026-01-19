import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._internal();

  static final NotificationService _instance =
      NotificationService._internal();

  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const initSettings = InitializationSettings(
      android: androidInit,
    );

    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  /// Simple test notification to verify that notifications are working.
  Future<void> showTestNotification() async {
    if (!_initialized) {
      await init();
    }

    const androidDetails = AndroidNotificationDetails(
      'test_channel_id',
      'Test Notifications',
      channelDescription: 'Channel for test notifications',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(
      android: androidDetails,
    );

    await _plugin.show(
      0,
      'Notifications enabled',
      'You will now receive EleagueHub notifications.',
      details,
    );
  }

  /// Notification for a league announcement (local to this device).
  Future<void> showLeagueAnnouncementNotification({
    required String leagueName,
    required String title,
    required String message,
  }) async {
    if (!_initialized) {
      await init();
    }

    const androidDetails = AndroidNotificationDetails(
      'league_announcements_channel',
      'League Announcements',
      channelDescription: 'Announcements from league admins',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(
      android: androidDetails,
    );

    final notifTitle = '$leagueName: $title';

    await _plugin.show(
      1, // arbitrary id for announcements
      notifTitle,
      message,
      details,
    );
  }
}
