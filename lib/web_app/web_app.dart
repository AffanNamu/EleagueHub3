import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import 'presentation/web_desktop_session_store.dart';
import 'presentation/web_desktop_shell_screen.dart';
import 'presentation/web_pairing_screen.dart';

class EleagueHubWebApp extends ConsumerWidget {
  const EleagueHubWebApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider).mode;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'eSportlyic Web',
      themeMode: themeMode,
      theme: AppTheme.skyTheme(),
      darkTheme: AppTheme.navyTheme(),
      home: const _WebRootGate(),
    );
  }
}

/// Decides whether to show QR pairing or shell based on localStorage.
/// Rebuilds on every hot restart and size change because it is the
/// MaterialApp home — not a pushed route.
class _WebRootGate extends StatefulWidget {
  const _WebRootGate();

  @override
  State<_WebRootGate> createState() => _WebRootGateState();
}

class _WebRootGateState extends State<_WebRootGate>
    with WidgetsBindingObserver {
  bool _checking = true;
  Map<String, String>? _savedSession;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  Future<void> _check() async {
    final saved = await WebDesktopSessionStore.load();
    if (!mounted) return;
    setState(() {
      _savedSession = saved;
      _checking = false;
    });
  }

  void _onPaired({
    required String uid,
    required String name,
    required String email,
  }) {
    if (!mounted) return;
    setState(() {
      _savedSession = {
        'pairedUserUid': uid,
        'pairedUserName': name,
        'pairedUserEmail': email,
        'sessionId': '',
        'sessionSecret': '',
      };
    });
  }

  void _onUnlink() {
    WebDesktopSessionStore.clear();
    if (!mounted) return;
    setState(() {
      _savedSession = null;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final session = _savedSession;
    final uid = (session?['pairedUserUid'] ?? '').trim();

    if (uid.isNotEmpty) {
      return WebDesktopShellScreen(
        pairedUserUid: uid,
        pairedUserName: session?['pairedUserName'] ?? '',
        pairedUserEmail: session?['pairedUserEmail'] ?? '',
        onUnlink: _onUnlink,
      );
    }

    return WebPairingScreen(
      onPaired: _onPaired,
    );
  }
}
