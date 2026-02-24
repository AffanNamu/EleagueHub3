import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';

import 'app_router.dart';
import 'auth_action_link.dart';

/// Listens for incoming deep links and navigates the app.
///
/// Supported link:
/// - esportlyic://auth?mode=resetPassword&oobCode=...
/// - esportlyic://auth?mode=verifyEmail&oobCode=...
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

    // Cold start
    unawaited(_handleInitialUri());

    // Warm links
    _sub = _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri);
    }, onError: (_) {
      // Ignore: do not crash on malformed links.
    });
  }

  Future<void> _handleInitialUri() async {
    try {
      // app_links 6.x API
      final uri = await _appLinks.getInitialLink();
      if (uri == null) return;
      _handleUri(uri);
    } catch (_) {
      // Ignore
    }
  }

  void _handleUri(Uri uri) {
    final action = AuthEmailActionLink.tryParse(uri);
    if (action == null) return;

    // Ensure navigation happens after router is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (action.mode) {
        case AuthEmailActionMode.resetPassword:
          appRouter.go('/reset-password?oobCode=${Uri.encodeQueryComponent(action.oobCode)}');
          return;
        case AuthEmailActionMode.verifyEmail:
          appRouter.go('/verify-email?oobCode=${Uri.encodeQueryComponent(action.oobCode)}');
          return;
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
