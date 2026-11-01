import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// User-safe exception: if UI accidentally shows `$e`, it will still be a friendly message.
class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

/// Global connectivity service (ONLINE-ONLY UX helper)
/// - Tracks online/offline state for UI (e.g., OfflineBanner)
/// - Verifies real internet access (not just network interface)
/// - Must NOT be used to enable offline mode or background sync
class ConnectivityService {
  ConnectivityService._internal();

  static final ConnectivityService instance = ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();

  /// True when device has confirmed internet access.
  /// Defaults to false until first check completes.
  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(false);

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _initialized = false;
  bool _disposed = false;
  Future<void>? _initializing;

  /// Must be called once (e.g. in main.dart). Safe to call multiple times.
  Future<void> initialize() {
    if (_disposed) return Future.value();
    if (_initialized) return Future.value();
    return _initializing ??= _initializeInternal();
  }

  Future<void> _initializeInternal() async {
    try {
      final results = await _connectivity.checkConnectivity();
      await _updateStatus(results);

      _subscription = _connectivity.onConnectivityChanged.listen(_updateStatus);
      _initialized = true;
    } catch (_) {
      // If connectivity plugin fails, treat as offline (safe default).
      _setConnected(false);
      _initialized = true;
    } finally {
      _initializing = null;
    }
  }

  /// Forces a manual recheck (e.g., "Retry" buttons / status cards).
  Future<bool> recheckConnection({Duration timeout = const Duration(seconds: 4)}) async {
    if (_disposed) return false;

    try {
      final results = await _connectivity.checkConnectivity().timeout(timeout);
      // `timeout` used to only bound this interface check, not the DNS
      // probe inside _updateStatus() -- which could still run up to
      // hosts.length * 2s (6s) past whatever budget a caller like
      // requireOnline(timeout: Duration(seconds: 4)) asked for.
      await _updateStatus(results).timeout(timeout);
      return isConnected.value;
    } catch (_) {
      // Ambiguous (a timeout or a plugin hiccup), not a confirmed "no
      // internet" -- keep the last known state rather than forcing
      // offline. requireOnline() gates writes across the whole app
      // (chat sends, uploads, league admin actions, ...), and wrongly
      // forcing "offline" here blocks an action that would very likely
      // have succeeded; a real lack of connectivity still surfaces its
      // own accurate error from the actual network call that follows.
      return isConnected.value;
    }
  }

  /// Online-only convenience:
  /// Throws a user-friendly exception if the device isn't online.
  Future<void> requireOnline({Duration timeout = const Duration(seconds: 4)}) async {
    await initialize();
    final ok = await recheckConnection(timeout: timeout);
    if (!ok) {
      throw const UserFriendlyException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    }
  }

  Future<void> _updateStatus(List<ConnectivityResult> results) async {
    if (_disposed) return;

    final hasNetwork =
        results.isNotEmpty && !results.contains(ConnectivityResult.none);

    if (!hasNetwork) {
      _setConnected(false);
      return;
    }

    final hasInternet = await _hasRealInternetAccess();
    _setConnected(hasInternet);
  }

  void _setConnected(bool connected) {
    if (_disposed) return;
    if (isConnected.value == connected) return;

    isConnected.value = connected;

    // Avoid bad state if someone calls after dispose.
    if (!_connectionController.isClosed) {
      _connectionController.add(connected);
    }
  }

  /// Real internet check (DNS lookup).
  /// Uses multiple hosts to reduce false negatives in restricted networks.
  ///
  /// WEB FIX:
  /// On Flutter Web, InternetAddress.lookup is unreliable / may fail even when
  /// the browser has internet. For web, if we have any connectivity signal
  /// from connectivity_plus, treat as online and let real network calls
  /// (Firestore/Auth/HTTP) decide.
  Future<bool> _hasRealInternetAccess() async {
    if (kIsWeb) return true;

    const hosts = <String>[
      'one.one.one.one', // Cloudflare
      'google.com',
      'example.com',
    ];

    // Checked in parallel, not one host at a time: a sequential loop
    // could take up to hosts.length * 2s (6s) to confirm "offline",
    // which made a slow-but-working network indistinguishable from a
    // genuinely dead one, and blew well past the few-second budget
    // every caller of requireOnline() expects. A single resolved host
    // is still enough to call it online.
    final oks = await Future.wait(hosts.map((host) async {
      try {
        final result =
            await InternetAddress.lookup(host).timeout(const Duration(seconds: 2));
        return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
      } catch (_) {
        return false;
      }
    }));
    return oks.any((ok) => ok);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;

    try {
      _subscription?.cancel();
    } catch (_) {}
    _subscription = null;

    try {
      _connectionController.close();
    } catch (_) {}
  }
}
