import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';

import 'app_router.dart';
import 'auth_action_link.dart';

/// Listens for incoming deep links and navigates the app.
///
/// Supported links:
///
/// AUTH links (password reset / email verify):
///   - esportlyic://auth?mode=resetPassword&oobCode=...
///   - esportlyic://auth?mode=verifyEmail&oobCode=...
///   - https://esportlyic.web.app/auth?mode=resetPassword&oobCode=...
///
/// JOIN links (league QR / share links):
///   - eleaguehub://join?code=XXXXXX&id=...
///     (old custom scheme — kept for backward compat with already-printed QRs)
///   - https://esportlyic.web.app/join?code=XXXXXX&id=...
///     (new HTTPS — web share links and new QR codes)
///   - https://esportlyic.web.app/join/XXXXXX
///     (path-segment form)
///
/// When a JOIN link is received the app navigates to /join?code=XXXXXX
/// which is a route registered in app_router.dart that works on both
/// web (shows inline code-entry join flow) and mobile (shows QR scanner
/// with the code pre-filled so the join runs automatically).
///
/// ---------------------------------------------------------------------------
/// WHY THIS WAS BROKEN BEFORE:
/// ---------------------------------------------------------------------------
/// 1. DeepLinkGate only handled AUTH links. JOIN links were silently ignored.
/// 2. My previous fix routed to '/scan' which does not exist in app_router.
/// 3. The correct route is '/join' (added to app_router in this fix set).
/// ---------------------------------------------------------------------------
class DeepLinkGate extends StatefulWidget {
  const DeepLinkGate({super.key, required this.child});
  final Widget child;

  @override
  State<DeepLinkGate> createState() => _DeepLinkGateState();
}

class _DeepLinkGateState extends State<DeepLinkGate> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  @override
  void initState() {
    super.initState();

    // Cold start — app opened by tapping a link.
    unawaited(_handleInitialUri());

    // Warm links — app already running, link received.
    _sub = _appLinks.uriLinkStream.listen(
      (uri) => _handleUri(uri),
      onError: (_) {
        // Ignore: do not crash on malformed links.
      },
    );
  }

  Future<void> _handleInitialUri() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri == null) return;
      _handleUri(uri);
    } catch (_) {
      // Ignore.
    }
  }

  void _handleUri(Uri uri) {
    // ── 1. Try AUTH links first ──────────────────────────────────────────────
    final action = AuthEmailActionLink.tryParse(uri);
    if (action != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        switch (action.mode) {
          case AuthEmailActionMode.resetPassword:
            appRouter.go(
              '/reset-password?oobCode=${Uri.encodeQueryComponent(action.oobCode)}',
            );
            return;
          case AuthEmailActionMode.verifyEmail:
            appRouter.go(
              '/verify-email?oobCode=${Uri.encodeQueryComponent(action.oobCode)}',
            );
            return;
        }
      });
      return;
    }

    // ── 2. Try JOIN links ────────────────────────────────────────────────────
    //
    // Routes to /join?code=XXXXXX which is registered in app_router.dart.
    // On web  → shows WebJoinScreen (inline code-entry + join flow).
    // On mobile → shows QRScannerScreen with code pre-filled.
    final joinCode = _tryParseJoinCode(uri);
    if (joinCode != null && joinCode.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appRouter.go(
          '/join?code=${Uri.encodeQueryComponent(joinCode.toUpperCase())}',
        );
      });
      return;
    }

    // ── 3. Unrecognised link — ignore silently ───────────────────────────────
  }

  /// Extracts a join code from any supported join URI shape.
  /// Returns null if the URI is not a join link.
  String? _tryParseJoinCode(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    final isCustomScheme = scheme == 'eleaguehub';
    final isWebDomain = host == 'esportlyic.web.app' ||
        host == 'esportlyic.firebaseapp.com';
    final isHttps = scheme == 'https' || scheme == 'http';

    // ── Custom scheme: eleaguehub://join?code=... ──────────────────────────
    if (isCustomScheme && path.contains('join')) {
      final code = (uri.queryParameters['code'] ?? '').trim();
      if (code.isNotEmpty) return code;

      // Path segment: eleaguehub://join/XXXXXX
      final segments = uri.pathSegments
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && s.toLowerCase() != 'join')
          .toList();
      if (segments.isNotEmpty) {
        final candidate = segments.last.toUpperCase();
        if (RegExp(r'^[A-Z0-9]{4,16}$').hasMatch(candidate)) {
          return candidate;
        }
      }
      return null;
    }

    // ── HTTPS web domain join links ─────────────────────────────────────────
    if (isHttps && isWebDomain && path.contains('join')) {
      // ?code= query parameter
      final code = (uri.queryParameters['code'] ?? '').trim();
      if (code.isNotEmpty) return code;

      // Path segment: /join/XXXXXX
      final segments = uri.pathSegments
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && s.toLowerCase() != 'join')
          .toList();
      if (segments.isNotEmpty) {
        final candidate = segments.last.toUpperCase();
        if (RegExp(r'^[A-Z0-9]{4,16}$').hasMatch(candidate)) {
          return candidate;
        }
      }
      return null;
    }

    return null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
