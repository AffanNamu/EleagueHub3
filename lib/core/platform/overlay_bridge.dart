import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Summary:
/// - Receives overlay actions from Android (WindowManager overlay + notification actions).
/// - Screens/features register handlers so overlay can control the currently active session.
/// - Keeps existing in-screen UI behavior intact; overlay is "extra control surface".
class OverlayBridge {
  static const MethodChannel _ch = MethodChannel('local_live');

  static bool _initialized = false;

  /// Handlers registered by the "currently active" feature.
  static Future<void> Function(bool enabled)? setMicEnabled;
  static Future<void> Function()? toggleMic;
  static Future<void> Function()? endSession;
  static Future<void> Function(String label)? sendQuick;

  /// Optional state query (not required for v1).
  static ValueListenable<bool>? micEnabledListenable;

  static void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;

    _ch.setMethodCallHandler((call) async {
      if (call.method != 'overlayAction') return;

      final args = call.arguments;
      if (args is! Map) return;

      final map = args.cast<dynamic, dynamic>();
      final action = (map['action'] ?? '').toString().trim().toLowerCase();

      try {
        switch (action) {
          case 'mute':
            await setMicEnabled?.call(false);
            break;
          case 'unmute':
            await setMicEnabled?.call(true);
            break;
          case 'toggle_mic':
            await toggleMic?.call();
            break;
          case 'end':
            await endSession?.call();
            break;
          case 'send_quick':
            final label = (map['label'] ?? '').toString();
            if (label.trim().isEmpty) return;
            await sendQuick?.call(label);
            break;
          case 'expand':
            // Android already expands app. Nothing required here.
            break;
          default:
            if (kDebugMode) {
              // ignore: avoid_print
              print('OverlayBridge: unknown action=$action args=$map');
            }
        }
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('OverlayBridge: action=$action failed: $e');
        }
      }
    });
  }

  static void clearHandlers() {
    setMicEnabled = null;
    toggleMic = null;
    endSession = null;
    sendQuick = null;
    micEnabledListenable = null;
  }
}
