import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final prefsServiceProvider = Provider<PreferencesService>((ref) {
  throw UnimplementedError('Override this in main()');
});

class PreferencesService {
  PreferencesService._(this._sp);
  final SharedPreferences _sp;

  static const _kThemeMode = 'theme_mode';
  static const _kLocaleCode = 'locale_code';
  static const _kLocaleManualOverride = 'locale_manual_override';

  /// Logged in user id key (Firebase Auth uid).
  static const String kCurrentUserIdKey = 'current_user_id';

  static Future<PreferencesService> create() async {
    final sp = await SharedPreferences.getInstance();
    return PreferencesService._(sp);
  }

  /// Standard helpers
  String? getString(String key) => _sp.getString(key);
  Future<void> setString(String key, String value) async {
    await _sp.setString(key, value);
  }

  int? getInt(String key) => _sp.getInt(key);
  Future<void> setInt(String key, int value) async {
    await _sp.setInt(key, value);
  }

  bool? getBool(String key) => _sp.getBool(key);
  Future<void> setBool(String key, bool value) async {
    await _sp.setBool(key, value);
  }

  Future<void> remove(String key) async {
    await _sp.remove(key);
  }

  /// Convenience helpers for current user id
  String? getCurrentUserId() => _sp.getString(kCurrentUserIdKey);

  Future<void> setCurrentUserId(String userId) async {
    await _sp.setString(kCurrentUserIdKey, userId);
  }

  Future<void> clearCurrentUserId() async {
    await _sp.remove(kCurrentUserIdKey);
  }

  /// Generic List helpers used by repositories
  List<String> getStringList(String key) => _sp.getStringList(key) ?? [];

  Future<void> setStringList(String key, List<String> value) async {
    await _sp.setStringList(key, value);
  }

  /// Theme persistence
  String? getThemeMode() => _sp.getString(_kThemeMode);
  Future<void> setThemeMode(String mode) async {
    await _sp.setString(_kThemeMode, mode);
  }

  /// Locale persistence
  String? getLocaleCode() => _sp.getString(_kLocaleCode);
  Future<void> setLocaleCode(String code) async {
    await _sp.setString(_kLocaleCode, code);
  }

  bool getLocaleManualOverride() => _sp.getBool(_kLocaleManualOverride) ?? false;
  Future<void> setLocaleManualOverride(bool value) async {
    await _sp.setBool(_kLocaleManualOverride, value);
  }

  Future<void> clearLocaleManualOverride() async {
    await _sp.remove(_kLocaleManualOverride);
  }

  /// Notification persistence (global app-level)
  Future<void> saveNotificationPrefs({
    required bool enabled,
    required bool marketing,
    required bool matchReminders,
  }) async {
    await _sp.setBool('notifications_enabled', enabled);
    await _sp.setBool('notifications_marketing', marketing);
    await _sp.setBool('notifications_match_reminders', matchReminders);
  }

  /// Load notification preferences with sane defaults.
  ///
  /// Defaults match what SettingsScreen expects:
  /// - enabled: true
  /// - marketing: false
  /// - matchReminders: true
  Future<Map<String, bool>> loadNotificationPrefs() async {
    final enabled = _sp.getBool('notifications_enabled');
    final marketing = _sp.getBool('notifications_marketing');
    final matchReminders = _sp.getBool('notifications_match_reminders');

    return {
      'enabled': enabled ?? true,
      'marketing': marketing ?? false,
      'matchReminders': matchReminders ?? true,
    };
  }

  /// Live viewer preferences (global)
  bool liveViewerChatEnabled() => _sp.getBool('live_viewer_chat_enabled') ?? true;
  bool liveViewerVoiceEnabled() => _sp.getBool('live_viewer_voice_enabled') ?? true;
  bool liveViewerReactionsEnabled() => _sp.getBool('live_viewer_reactions_enabled') ?? true;

  Future<void> setLiveViewerChatEnabled(bool value) async => setBool('live_viewer_chat_enabled', value);
  Future<void> setLiveViewerVoiceEnabled(bool value) async => setBool('live_viewer_voice_enabled', value);
  Future<void> setLiveViewerReactionsEnabled(bool value) async => setBool('live_viewer_reactions_enabled', value);

  /// Live overlay bubble (floating icon) global flag
  ///
  /// IMPORTANT:
  /// - Must be explicitly enabled by the user (requirement).
  /// - Therefore default is FALSE.
  bool liveOverlayEnabled() => _sp.getBool('live_overlay_enabled') ?? false;

  Future<void> setLiveOverlayEnabled(bool value) async => setBool('live_overlay_enabled', value);
}
