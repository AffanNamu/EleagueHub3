import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

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

  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _initialized = false;
  Future<void>? _initializing;

  /// Must be called once (e.g. in main.dart). Safe to call multiple times.
  Future<void> initialize() {
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
    try {
      final results = await _connectivity.checkConnectivity().timeout(timeout);
      await _updateStatus(results);
      return isConnected.value;
    } catch (_) {
      _setConnected(false);
      return false;
    }
  }

  Future<void> _updateStatus(List<ConnectivityResult> results) async {
    final hasNetwork = results.isNotEmpty && !results.contains(ConnectivityResult.none);

    if (!hasNetwork) {
      _setConnected(false);
      return;
    }

    final hasInternet = await _hasRealInternetAccess();
    _setConnected(hasInternet);
  }

  void _setConnected(bool connected) {
    if (isConnected.value == connected) return;
    isConnected.value = connected;
    _connectionController.add(connected);
  }

  /// Real internet check (DNS lookup).
  /// Uses multiple hosts to reduce false negatives in restricted networks.
  Future<bool> _hasRealInternetAccess() async {
    const hosts = <String>[
      'one.one.one.one', // Cloudflare
      'google.com',
      'example.com',
    ];

    for (final host in hosts) {
      try {
        final result = await InternetAddress.lookup(host).timeout(const Duration(seconds: 2));
        if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) return true;
      } catch (_) {
        // try next host
      }
    }
    return false;
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _connectionController.close();
  }
}
