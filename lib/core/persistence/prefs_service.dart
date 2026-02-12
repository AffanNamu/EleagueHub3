import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final prefsServiceProvider = Provider<PreferencesService>((ref) {
  throw UnimplementedError('Override this in main()');
});

/// ONLINE-ONLY STORAGE POLICY
/// --------------------------
/// SharedPreferences may ONLY be used for minimal UI flags (theme/locale/toggles).
/// It must NEVER be used as a domain cache (leagues/teams/matches/memberships/etc).
///
/// Enforcement approach:
/// - Allowlist known UI-only keys/prefixes.
/// - Block everything else by default.
/// This prevents new “offline caching” from being accidentally reintroduced via new keys.
class PreferencesService {
  PreferencesService._(this._sp);
  final SharedPreferences _sp;

  static const _kThemeMode = 'theme_mode';
  static const _kLocaleCode = 'locale_code';
  static const _kLocaleManualOverride = 'locale_manual_override';

  /// Legacy key (DO NOT use for auth decisions).
  ///
  /// ONLINE-ONLY RULE:
  /// - Never assume auth state from local storage.
  /// - Always verify `FirebaseAuth.instance.currentUser`.
  @Deprecated('Online-only: do not persist auth uid locally for access control.')
  static const String kCurrentUserIdKey = 'current_user_id';

  // -------------------------
  // Allowlist (UI-only)
  // -------------------------

  static const Set<String> _allowedExactKeys = <String>{
    // Theme / locale
    _kThemeMode,
    _kLocaleCode,
    _kLocaleManualOverride,

    // Notifications (UI preference only)
    'notifications_enabled',
    'notifications_marketing',
    'notifications_match_reminders',

    // Live viewer toggles (UI-only)
    'live_viewer_chat_enabled',
    'live_viewer_voice_enabled',
    'live_viewer_reactions_enabled',

    // Live overlay bubble toggle (UI-only)
    'live_overlay_enabled',
  };

  static const List<String> _allowedPrefixes = <String>[
    // Reserved for future UI-only flags (do NOT store domain data under these).
    'ui_',
  ];

  // -------------------------
  // Blocklist (legacy offline-first domain caching keys)
  // -------------------------

  static const Set<String> _blockedExactKeys = <String>{
    // Offline sync / caching artifacts
    'sync_queue_items',
    'cloud_last_pulled_at_ms',

    // Domain caches (must never persist locally)
    'local_leagues',
    'local_memberships',
    'local_teams',
    'local_matches',
    'local_knockout_matches',

    // Legacy cached auth identity
    kCurrentUserIdKey,
  };

  static const List<String> _blockedPrefixes = <String>[
    // Legacy offline-first caching prefixes
    'league_announcements_',
    'league_space_',
  ];

  static Future<PreferencesService> create() async {
    final sp = await SharedPreferences.getInstance();
    return PreferencesService._(sp);
  }

  bool _isAllowedKey(String key) {
    if (_allowedExactKeys.contains(key)) return true;
    for (final p in _allowedPrefixes) {
      if (key.startsWith(p)) return true;
    }
    return false;
  }

  bool _isBlockedKey(String key) {
    if (_blockedExactKeys.contains(key)) return true;
    for (final p in _blockedPrefixes) {
      if (key.startsWith(p)) return true;
    }
    return false;
  }

  bool _shouldBlock(String key) {
    // Blocklist always wins.
    if (_isBlockedKey(key)) return true;

    // Online-only: block anything not explicitly allowlisted.
    return !_isAllowedKey(key);
  }

  void _debugBlocked(String method, String key) {
    if (kDebugMode) {
      debugPrint('PreferencesService($method) blocked key="$key" (online-only).');
    }
  }

  /// -------------------------
  /// Generic helpers (STRICT: allowlist only)
  /// -------------------------

  String? getString(String key) {
    if (_shouldBlock(key)) return null;
    return _sp.getString(key);
  }

  Future<void> setString(String key, String value) async {
    if (_shouldBlock(key)) {
      _debugBlocked('setString', key);
      return;
    }
    await _sp.setString(key, value);
  }

  int? getInt(String key) {
    if (_shouldBlock(key)) return null;
    return _sp.getInt(key);
  }

  Future<void> setInt(String key, int value) async {
    if (_shouldBlock(key)) {
      _debugBlocked('setInt', key);
      return;
    }
    await _sp.setInt(key, value);
  }

  bool? getBool(String key) {
    if (_shouldBlock(key)) return null;
    return _sp.getBool(key);
  }

  Future<void> setBool(String key, bool value) async {
    if (_shouldBlock(key)) {
      _debugBlocked('setBool', key);
      return;
    }
    await _sp.setBool(key, value);
  }

  Future<void> remove(String key) async {
    if (_shouldBlock(key)) {
      _debugBlocked('remove', key);
      return;
    }
    await _sp.remove(key);
  }

  /// -------------------------
  /// Legacy: current user id (blocked for auth decisions)
  /// -------------------------

  @Deprecated('Online-only: do not persist auth uid locally for access control.')
  String? getCurrentUserId() => null;

  @Deprecated('Online-only: do not persist auth uid locally for access control.')
  Future<void> setCurrentUserId(String userId) async {
    _debugBlocked('setCurrentUserId', kCurrentUserIdKey);
  }

  @Deprecated('Online-only: do not persist auth uid locally for access control.')
  Future<void> clearCurrentUserId() async {
    // Ensure it is removed if it exists from old installs.
    await _sp.remove(kCurrentUserIdKey);
  }

  /// -------------------------
  /// Generic List helpers (STRICT: allowlist only)
  /// -------------------------

  List<String> getStringList(String key) {
    if (_shouldBlock(key)) return const <String>[];
    return _sp.getStringList(key) ?? const <String>[];
  }

  Future<void> setStringList(String key, List<String> value) async {
    if (_shouldBlock(key)) {
      _debugBlocked('setStringList', key);
      return;
    }
    await _sp.setStringList(key, value);
  }

  /// -------------------------
  /// Theme persistence (UI-only)
  /// -------------------------

  String? getThemeMode() => _sp.getString(_kThemeMode);

  Future<void> setThemeMode(String mode) async {
    await _sp.setString(_kThemeMode, mode);
  }

  /// -------------------------
  /// Locale persistence (UI-only)
  /// -------------------------

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

  /// -------------------------
  /// Notification persistence (UI-only)
  /// -------------------------

  Future<void> saveNotificationPrefs({
    required bool enabled,
    required bool marketing,
    required bool matchReminders,
  }) async {
    await _sp.setBool('notifications_enabled', enabled);
    await _sp.setBool('notifications_marketing', marketing);
    await _sp.setBool('notifications_match_reminders', matchReminders);
  }

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

  /// -------------------------
  /// Live viewer prefs (UI-only)
  /// -------------------------

  bool liveViewerChatEnabled() => _sp.getBool('live_viewer_chat_enabled') ?? true;
  bool liveViewerVoiceEnabled() => _sp.getBool('live_viewer_voice_enabled') ?? true;
  bool liveViewerReactionsEnabled() => _sp.getBool('live_viewer_reactions_enabled') ?? true;

  Future<void> setLiveViewerChatEnabled(bool value) async => setBool('live_viewer_chat_enabled', value);
  Future<void> setLiveViewerVoiceEnabled(bool value) async => setBool('live_viewer_voice_enabled', value);
  Future<void> setLiveViewerReactionsEnabled(bool value) async => setBool('live_viewer_reactions_enabled', value);

  /// -------------------------
  /// Live overlay bubble flag (UI-only)
  /// -------------------------

  bool liveOverlayEnabled() => _sp.getBool('live_overlay_enabled') ?? false;

  Future<void> setLiveOverlayEnabled(bool value) async => setBool('live_overlay_enabled', value);
}
