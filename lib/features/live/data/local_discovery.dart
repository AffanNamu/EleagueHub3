import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/services/connectivity_service.dart';
import 'local_lan_ip.dart';

const int kLocalLiveDiscoveryPort = 54545;

/// User-safe exception: if UI accidentally shows `$e`, it will still be a friendly message.
class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

/// Optional hint so viewers can map hosts to the correct side.
enum LiveHostSide { home, away, unknown }

LiveHostSide parseLiveHostSide(String? v) {
  switch ((v ?? '').toLowerCase().trim()) {
    case 'home':
      return LiveHostSide.home;
    case 'away':
      return LiveHostSide.away;
    default:
      return LiveHostSide.unknown;
  }
}

String liveHostSideToWire(LiveHostSide side) {
  switch (side) {
    case LiveHostSide.home:
      return 'home';
    case LiveHostSide.away:
      return 'away';
    case LiveHostSide.unknown:
      return 'unknown';
  }
}

Future<void> _requireSignedInAndOnline() async {
  final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  if (uid.isEmpty) {
    throw const UserFriendlyException('Please sign in and try again.');
  }

  await ConnectivityService.instance.initialize();
  final ok = await ConnectivityService.instance.recheckConnection(timeout: const Duration(seconds: 4));
  if (!ok) {
    throw const UserFriendlyException(
      'Your network appears to be offline. Please check your connection and try again.',
    );
  }
}

class DiscoveredHost {
  DiscoveredHost({
    required this.hostIp,
    required this.port,
    required this.matchId,
    required this.lastSeen,
    this.deviceName,
    this.homeName,
    this.awayName,
    this.side = LiveHostSide.unknown,
  });

  final String hostIp;
  final int port;
  final String matchId;
  final DateTime lastSeen;

  final String? deviceName;

  /// Optional match labels broadcast by host
  final String? homeName;
  final String? awayName;

  /// Optional home/away hint
  final LiveHostSide side;

  String get key => '$hostIp:$port/$matchId';

  DiscoveredHost copyWith({DateTime? lastSeen}) => DiscoveredHost(
        hostIp: hostIp,
        port: port,
        matchId: matchId,
        lastSeen: lastSeen ?? this.lastSeen,
        deviceName: deviceName,
        homeName: homeName,
        awayName: awayName,
        side: side,
      );
}

/// Host side: broadcasts "I'm hosting matchId on port" on LAN using UDP broadcast.
///
/// ONLINE-ONLY ENFORCEMENT:
/// This can never start when the device is offline/unreachable.
/// (Prevents the Live feature from functioning offline.)
class LocalLiveDiscoveryBroadcaster {
  LocalLiveDiscoveryBroadcaster({
    required this.matchId,
    required this.port,
    this.deviceName,
    this.homeName,
    this.awayName,
    this.side = LiveHostSide.unknown,
  });

  final String matchId;
  final int port;

  final String? deviceName;
  final String? homeName;
  final String? awayName;
  final LiveHostSide side;

  RawDatagramSocket? _socket;
  Timer? _timer;
  String? _localIp;
  List<InternetAddress> _targets = const [];

  Future<void> start() async {
    if (_socket != null) return;

    // ONLINE-ONLY: never allow discovery to run while offline.
    await _requireSignedInAndOnline();

    _localIp = await LocalLanIp.findLocalIpv4();

    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.broadcastEnabled = true;

    _targets = await _computeBroadcastTargets(_localIp);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final payload = jsonEncode({
        'type': 'eleaguehub-live',
        'matchId': matchId,
        'port': port,
        'ip': _localIp,
        'deviceName': deviceName,
        'homeName': homeName,
        'awayName': awayName,
        'side': liveHostSideToWire(side),
        'ts': DateTime.now().millisecondsSinceEpoch,
      });

      final data = utf8.encode(payload);

      for (final t in _targets) {
        try {
          _socket?.send(data, t, kLocalLiveDiscoveryPort);
        } catch (_) {
          // ignore
        }
      }
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;

    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  Future<List<InternetAddress>> _computeBroadcastTargets(String? localIp) async {
    final targets = <InternetAddress>[];

    // Global broadcast (some routers block it but try anyway)
    targets.add(InternetAddress('255.255.255.255'));

    // Best-effort /24 broadcast from local IP
    if (localIp != null) {
      final parts = localIp.split('.');
      if (parts.length == 4) {
        targets.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
      }
    }

    // Also try per-interface /24 broadcasts
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          final p = ip.split('.');
          if (p.length == 4) {
            targets.add(InternetAddress('${p[0]}.${p[1]}.${p[2]}.255'));
          }
        }
      }
    } catch (_) {
      // ignore
    }

    // de-dup
    final seen = <String>{};
    final out = <InternetAddress>[];
    for (final t in targets) {
      if (seen.add(t.address)) out.add(t);
    }
    return out;
  }
}

/// Viewer side: listens for LAN broadcasts and maintains a list of discovered hosts.
///
/// ONLINE-ONLY ENFORCEMENT:
/// This can never start when the device is offline/unreachable.
class LocalLiveDiscoveryListener {
  RawDatagramSocket? _socket;
  Timer? _cleanupTimer;

  final ValueNotifier<List<DiscoveredHost>> hosts = ValueNotifier<List<DiscoveredHost>>([]);

  final Map<String, DiscoveredHost> _byKey = {};

  Future<void> start() async {
    if (_socket != null) return;

    // ONLINE-ONLY: never allow discovery to run while offline.
    await _requireSignedInAndOnline();

    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      kLocalLiveDiscoveryPort,
      reuseAddress: true,
      reusePort: true,
    );

    _socket!.listen((evt) {
      if (evt != RawSocketEvent.read) return;
      final dg = _socket!.receive();
      if (dg == null) return;

      try {
        final msg = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
        if (msg['type'] != 'eleaguehub-live') return;

        final matchId = (msg['matchId'] ?? '').toString();
        final port = (msg['port'] as num?)?.toInt() ?? -1;
        if (matchId.isEmpty || port <= 0) return;

        final ip = (msg['ip'] as String?)?.trim();
        final hostIp = (ip != null && ip.isNotEmpty) ? ip : dg.address.address;

        final deviceName = (msg['deviceName'] as String?)?.trim();
        final homeName = (msg['homeName'] as String?)?.trim();
        final awayName = (msg['awayName'] as String?)?.trim();
        final side = parseLiveHostSide(msg['side'] as String?);

        final now = DateTime.now();
        final h = DiscoveredHost(
          hostIp: hostIp,
          port: port,
          matchId: matchId,
          lastSeen: now,
          deviceName: (deviceName == null || deviceName.isEmpty) ? null : deviceName,
          homeName: (homeName == null || homeName.isEmpty) ? null : homeName,
          awayName: (awayName == null || awayName.isEmpty) ? null : awayName,
          side: side,
        );

        _byKey[h.key] = h;
        _emit();
      } catch (_) {
        // ignore bad packets
      }
    });

    _cleanupTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final now = DateTime.now();
      _byKey.removeWhere(
        (_, h) => now.difference(h.lastSeen) > const Duration(seconds: 6),
      );
      _emit();
    });
  }

  void _emit() {
    final list = _byKey.values.toList()..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    hosts.value = list;
  }

  Future<void> stop() async {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;

    hosts.value = [];
    _byKey.clear();
  }
}
