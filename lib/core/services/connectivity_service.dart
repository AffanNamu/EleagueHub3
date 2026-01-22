import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Global connectivity service
/// - Handles online/offline state
/// - Verifies real internet access (not just network)
/// - Safe for app-wide usage
/// - Sync-friendly
class ConnectivityService {
  ConnectivityService._internal();

  static final ConnectivityService instance =
      ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();

  /// True when device has confirmed internet access
  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(true);

  /// Stream for services (sync, admin, background tasks)
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// Must be called once (e.g. in main.dart)
  Future<void> initialize() async {
    final results = await _connectivity.checkConnectivity();
    await _updateStatus(results);

    _subscription =
        _connectivity.onConnectivityChanged.listen(_updateStatus);
  }

  /// Forces a manual recheck (used by sync engine)
  Future<bool> recheckConnection() async {
    final results = await _connectivity.checkConnectivity();
    await _updateStatus(results);
    return isConnected.value;
  }

  Future<void> _updateStatus(List<ConnectivityResult> results) async {
    final hasNetwork =
        results.isNotEmpty && !results.contains(ConnectivityResult.none);

    bool hasInternet = false;

    if (hasNetwork) {
      hasInternet = await _hasRealInternetAccess();
    }

    if (isConnected.value != hasInternet) {
      isConnected.value = hasInternet;
      _connectionController.add(hasInternet);
    }
  }

  /// Real internet check (DNS ping)
  Future<bool> _hasRealInternetAccess() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Call only on app shutdown (usually not needed)
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _connectionController.close();
  }
}
