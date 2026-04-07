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

/// Web root gate:
/// - Large screens: desktop pairing / desktop shell
/// - Small screens: informational fallback instead of desktop companion flow
class _WebRootGate extends StatefulWidget {
  const _WebRootGate();

  @override
  State<_WebRootGate> createState() => _WebRootGateState();
}

class _WebRootGateState extends State<_WebRootGate>
    with WidgetsBindingObserver {
  static const double _desktopMinWidth = 760;

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
    final width = MediaQuery.of(context).size.width;
    final isDesktopWidth = width >= _desktopMinWidth;

    if (_checking) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!isDesktopWidth) {
      return const _SmallScreenWebFallback();
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

class _SmallScreenWebFallback extends StatelessWidget {
  const _SmallScreenWebFallback();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      backgroundColor: brightness == Brightness.dark
          ? const Color(0xFF08131F)
          : const Color(0xFFF4F7FB),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor(brightness),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppTheme.cardBorder(brightness),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: AppTheme.limeAccent,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.desktop_windows_rounded,
                        color: AppTheme.darkText,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'eSportlyic Web works best on a larger screen',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.primaryText(brightness),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Open this page on a desktop or tablet-sized browser window to pair your account and use the web dashboard.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.secondaryText(brightness),
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'If you are already on desktop, widen the browser window and refresh.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.secondaryText(brightness),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
