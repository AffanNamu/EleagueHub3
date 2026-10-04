// lib/features/football_hub/data/football_cache_service.dart
//
// Persistent (survives app restart) stale-while-revalidate cache for
// Football Hub API responses, keyed by endpoint+params.
//
// NOTE on lib/core/persistence/prefs_service.dart's "online-only" policy:
// that service explicitly blocks using SharedPreferences as a *domain*
// cache (leagues/teams/matches/memberships kept around to simulate being
// offline). This is deliberately NOT that: every entry carries a
// fetchedAtMs the caller checks against a TTL before trusting it, a
// cache miss or expired entry always triggers a real network call, and
// nothing here is ever treated as a substitute for being online -- it only
// exists to stop the same screen reload (or the same date re-tapped, or
// the app being closed and reopened) from re-issuing an identical API call
// that would return the same answer anyway. Mirrors the same
// SharedPreferences-direct, debounced-persist pattern already used by
// lib/core/services/chat_media_cache_service.dart (also a deliberate,
// documented exception to the same policy, for the same reason: this is a
// response cache with an expiry, not an offline domain store).
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class FootballCacheEntry {
  final Map<String, dynamic> data;
  final int fetchedAtMs;
  const FootballCacheEntry({required this.data, required this.fetchedAtMs});

  bool isFreshFor(Duration ttl) =>
      DateTime.now().millisecondsSinceEpoch - fetchedAtMs < ttl.inMilliseconds;
}

class FootballCacheService {
  FootballCacheService._();
  static final FootballCacheService instance = FootballCacheService._();

  static const _prefsKey = 'football_hub_api_cache_v1';
  // Keeps the persisted blob small and bounded even with the Leagues tab's
  // per-keystroke search (each distinct substring typed is its own key) and
  // months of accumulated per-date fixture lookups.
  static const _maxEntries = 300;

  final Map<String, FootballCacheEntry> _entries = {};
  bool _loaded = false;
  Future<void>? _loading;
  Timer? _persistTimer;

  Future<void> _ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (value is! Map) return;
            final data = value['data'];
            final fetchedAtMs = value['fetchedAtMs'];
            if (data is Map && fetchedAtMs is int) {
              _entries[key as String] = FootballCacheEntry(
                data: data.cast<String, dynamic>(),
                fetchedAtMs: fetchedAtMs,
              );
            }
          });
        }
      }
    } catch (_) {
      // Corrupt/unreadable cache -- start empty rather than crash over it.
    } finally {
      _loaded = true;
    }
  }

  Future<FootballCacheEntry?> get(String key) async {
    await _ensureLoaded();
    return _entries[key];
  }

  Future<void> put(String key, Map<String, dynamic> data) async {
    await _ensureLoaded();
    _entries[key] = FootballCacheEntry(
      data: data,
      fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _evictOldestIfOverBudget();
    _schedulePersist();
  }

  void _evictOldestIfOverBudget() {
    if (_entries.length <= _maxEntries) return;
    final byAge = _entries.keys.toList()
      ..sort((a, b) => _entries[a]!.fetchedAtMs.compareTo(_entries[b]!.fetchedAtMs));
    for (var i = 0; i < _entries.length - _maxEntries; i++) {
      _entries.remove(byAge[i]);
    }
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 800), _persist);
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{
        for (final e in _entries.entries)
          e.key: {'data': e.value.data, 'fetchedAtMs': e.value.fetchedAtMs},
      };
      await prefs.setString(_prefsKey, jsonEncode(map));
    } catch (_) {
      // Best-effort -- a failed persist just means the next cold start
      // re-fetches instead of reading a stale write; never crash over it.
    }
  }
}
