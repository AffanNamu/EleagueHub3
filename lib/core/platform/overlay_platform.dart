import 'dart:io';

import 'package:flutter/services.dart';

/// Summary:
/// - Single Android platform channel API for overlay + overlay voice foreground service.
/// - No iOS-op behavior.
class OverlayPlatform {
  static const MethodChannel _ch = MethodChannel('local_live');

  static Future<bool> isOverlayPermissionGranted() async {
    if (!Platform.isAndroid) return false;
    final res = await _ch.invokeMethod<bool>('isOverlayPermissionGranted');
    return res ?? false;
  }

  static Future<void> requestOverlayPermission() async {
    if (!Platform.isAndroid) return;
    await _ch.invokeMethod('requestOverlayPermission');
  }

  static Future<void> startGlobalOverlay() async {
    if (!Platform.isAndroid) return;
    // alias method implemented in MainActivity (keeps older names stable)
    await _ch.invokeMethod('startGlobalOverlay');
  }

  static Future<void> stopGlobalOverlay() async {
    if (!Platform.isAndroid) return;
    await _ch.invokeMethod('stopGlobalOverlay');
  }

  static Future<void> startOverlayVoiceForegroundService({
    String title = 'Voice chat',
    String text = 'Voice chat is running',
  }) async {
    if (!Platform.isAndroid) return;
    await _ch.invokeMethod('startOverlayVoiceForegroundService', {
      'title': title,
      'text': text,
    });
  }

  static Future<void> stopOverlayVoiceForegroundService() async {
    if (!Platform.isAndroid) return;
    await _ch.invokeMethod('stopOverlayVoiceForegroundService');
  }
}
