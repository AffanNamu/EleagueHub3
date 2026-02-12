import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/connectivity_service.dart';
import 'foreground_streaming_service.dart';
import 'live_quality.dart';
import 'local_discovery.dart';
import 'local_webrtc_host.dart';
import 'local_webrtc_viewer.dart';

/// User-safe exception: if UI accidentally shows `$e`, it will still be a friendly message.
class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

/// ONLINE-ONLY guard:
/// Local LAN live streaming must NOT run offline.
/// We enforce this at the service layer so callers cannot bypass UI gating.
class LocalLiveService {
  LocalLiveService._();
  static final LocalLiveService instance = LocalLiveService._();

  LocalLiveHostSession? _host;

  // Viewer is often managed directly by LiveViewScreen (can connect to two hosts).
  LocalLiveViewerSession? _viewer;

  LocalLiveHostSession? get activeHost => _host;
  LocalLiveViewerSession? get activeViewer => _viewer;

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

  Future<LocalLiveHostSession> startHostSession({
    required String liveMatchId,
    int port = 8765,
    String? homeName,
    String? awayName,
    LiveHostSide side = LiveHostSide.unknown,
    LiveQualityPreset quality = LiveQualityPreset.medium,
  }) async {
    await _requireSignedInAndOnline();

    await stopHostSession(liveMatchId: liveMatchId);

    final cfg = LiveCaptureConfig.fromPreset(quality);

    // Keep the process alive in background while gaming (best-effort).
    try {
      await ForegroundStreamingService.start(
        matchId: liveMatchId,
        title: 'Live: ${(homeName ?? '').trim()}${awayName != null ? ' vs ${awayName!.trim()}' : ''}'.trim(),
        text: 'Streaming active • ${qualityLabel(quality)}',
      );
    } catch (_) {
      // Non-fatal.
    }

    final host = LocalLiveHostSession(
      liveMatchId: liveMatchId,
      port: port,
      captureConfig: cfg,
      homeName: homeName,
      awayName: awayName,
      side: side,
    );

    _host = host;
    await host.start();
    return host;
  }

  Future<void> stopHostSession({required String liveMatchId}) async {
    final host = _host;
    if (host == null) return;
    if (host.liveMatchId != liveMatchId) return;

    await host.stop();
    _host = null;

    try {
      await ForegroundStreamingService.stop();
    } catch (_) {
      // ignore
    }
  }

  /// Legacy single-viewer join (still used by some flows)
  Future<LocalLiveViewerSession> joinViewerSession({
    required String liveMatchId,
    required String host,
    required int port,
  }) async {
    await _requireSignedInAndOnline();

    await leaveViewerSession(liveMatchId: liveMatchId);

    final viewer = LocalLiveViewerSession(
      liveMatchId: liveMatchId,
      host: host,
      port: port,
    );
    _viewer = viewer;
    await viewer.connect();
    return viewer;
  }

  Future<void> leaveViewerSession({required String liveMatchId}) async {
    final viewer = _viewer;
    if (viewer == null) return;
    if (viewer.liveMatchId != liveMatchId) return;

    await viewer.disconnect();
    _viewer = null;
  }

  void broadcastHostEvent({
    required String liveMatchId,
    required Map<String, dynamic> event,
  }) {
    final host = _host;
    if (host == null) return;
    if (host.liveMatchId != liveMatchId) return;

    host.broadcastEvent(event);
  }
}
