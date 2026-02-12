import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Best-effort Android foreground service helper.
///
/// ONLINE-ONLY NOTE:
/// This does not enable offline mode. It's purely to keep the process alive
/// during an active online live session (so token/room connection isn't killed).
class ForegroundStreamingService {
  static const _ch = MethodChannel('local_live');

  /// Start foreground service so the app keeps running while user switches to game.
  static Future<void> start({
    required String matchId,
    String? title,
    String? text,
  }) async {
    if (!Platform.isAndroid) return;

    try {
      // Android 13+ needs notification permission for foreground-service notification.
      // Some devices will crash/deny startForeground without it.
      final notif = await Permission.notification.status;
      if (!notif.isGranted) {
        await Permission.notification.request();
      }

      await _ch
          .invokeMethod('startForegroundStreamingService', {
            'title': title ?? 'Live match: $matchId',
            'text': text ?? 'Streaming is active',
          })
          .timeout(const Duration(seconds: 4));
    } on TimeoutException {
      // Best-effort: don't crash the app over this.
      return;
    } on PlatformException {
      // Best-effort: don't crash the app over this.
      return;
    } catch (_) {
      return;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;

    try {
      await _ch.invokeMethod('stopForegroundStreamingService').timeout(const Duration(seconds: 4));
    } on TimeoutException {
      return;
    } on PlatformException {
      return;
    } catch (_) {
      return;
    }
  }
}
