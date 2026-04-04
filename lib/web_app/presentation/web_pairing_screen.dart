import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/desktop/desktop_pairing_models.dart';
import '../../core/services/desktop/desktop_pairing_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/glass_scaffold.dart';
import 'web_desktop_session_store.dart';
import 'web_desktop_shell_screen.dart';

class WebPairingScreen extends StatefulWidget {
  const WebPairingScreen({super.key});

  @override
  State<WebPairingScreen> createState() => _WebPairingScreenState();
}

class _WebPairingScreenState extends State<WebPairingScreen> {
  static const Color _accent = AppTheme.navyAccent;
  static const Color _bg = AppTheme.navyBg;

  DesktopPairingSession? _session;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final existing = await WebDesktopSessionStore.load();
      if (existing != null && mounted) {
        _openShell(
          pairedUserUid: existing['pairedUserUid'] ?? '',
          pairedUserName: existing['pairedUserName'] ?? '',
          pairedUserEmail: existing['pairedUserEmail'] ?? '',
        );
        return;
      }

      final session = await DesktopPairingService.instance.createSession();
      if (!mounted) return;

      setState(() {
        _session = session;
        _loading = false;
      });

      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();

    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final current = _session;
      if (current == null) return;

      try {
        final status = await DesktopPairingService.instance.getStatus(
          sessionId: current.sessionId,
          sessionSecret: current.sessionSecret,
        );

        if (!mounted) return;

        if (status.approved ||
            status.status == 'approved' ||
            status.status == 'consumed') {
          _pollTimer?.cancel();

          await WebDesktopSessionStore.save(
            sessionId: current.sessionId,
            sessionSecret: current.sessionSecret,
            pairedUserUid: status.pairedUserUid,
            pairedUserName: status.pairedUserName,
            pairedUserEmail: status.pairedUserEmail,
          );

          if (!mounted) return;

          _openShell(
            pairedUserUid: status.pairedUserUid,
            pairedUserName: status.pairedUserName,
            pairedUserEmail: status.pairedUserEmail,
          );
          return;
        }

        if (status.status == 'expired' || status.status == 'rejected') {
          _pollTimer?.cancel();
          if (!mounted) return;
          setState(() {
            _error = 'This desktop session expired. Please refresh and scan again.';
          });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = e.toString();
        });
      }
    });
  }

  void _openShell({
    required String pairedUserUid,
    required String pairedUserName,
    required String pairedUserEmail,
  }) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WebDesktopShellScreen(
          pairedUserUid: pairedUserUid,
          pairedUserName: pairedUserName,
          pairedUserEmail: pairedUserEmail,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final compact = width < 640;
            final stacked = width < 980;

            if (_loading) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _InfoCard(
                      title: 'Preparing desktop session...',
                      subtitle:
                          'Please wait while we generate your eSportlyic Web QR login.',
                      child: const Padding(
                        padding: EdgeInsets.only(top: 18),
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            if (_error != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _InfoCard(
                      title: 'Could not start desktop pairing',
                      subtitle: _error!,
                      child: Column(
                        children: [
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: () async {
                              await WebDesktopSessionStore.clear();
                              _boot();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            final session = _session;
            if (session == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _InfoCard(
                      title: 'No session available',
                      subtitle: 'Tap refresh to create a new QR session.',
                      child: Column(
                        children: [
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: _boot,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            final introPanel = _IntroPanel(compact: compact);
            final qrPanel = _QrPanel(
              session: session,
              onRefresh: _boot,
              compact: compact,
            );

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1220),
                  child: stacked
                      ? Column(
                          children: [
                            qrPanel,
                            const SizedBox(height: 16),
                            introPanel,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: introPanel),
                            const SizedBox(width: 18),
                            Expanded(flex: 7, child: qrPanel),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _InfoCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 28,
      padding: const EdgeInsets.all(24),
      fill: Colors.white.withOpacity(0.08),
      borderColor: Colors.white.withOpacity(0.12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _IntroPanel extends StatelessWidget {
  final bool compact;

  const _IntroPanel({
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 28,
      padding: EdgeInsets.all(compact ? 18 : 24),
      fill: Colors.white.withOpacity(0.08),
      borderColor: Colors.white.withOpacity(0.12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _BrandLogo(size: compact ? 54 : 64),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'eSportlyic Web',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: compact ? 28 : 36,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            compact
                ? 'Open eSportlyic on another device'
                : 'Use eSportlyic on your computer',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                  fontSize: compact ? 28 : 54,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            '1. Open eSportlyic on your phone\n'
            '2. Go to the QR scanner\n'
            '3. Scan this code to link your desktop',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withOpacity(0.84),
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 18 : 22,
                ),
          ),
          const SizedBox(height: 18),
          Glass(
            borderRadius: 22,
            padding: const EdgeInsets.all(16),
            fill: Colors.white.withOpacity(0.05),
            borderColor: Colors.white.withOpacity(0.10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  color: AppTheme.navyAccent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your phone stays the primary device. This desktop session is linked securely through your mobile app.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QrPanel extends StatelessWidget {
  final DesktopPairingSession session;
  final VoidCallback onRefresh;
  final bool compact;

  const _QrPanel({
    required this.session,
    required this.onRefresh,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final qrSize = compact ? 220.0 : (width < 1200 ? 260.0 : 300.0);

    return Glass(
      borderRadius: 28,
      padding: EdgeInsets.all(compact ? 18 : 24),
      fill: Colors.white.withOpacity(0.08),
      borderColor: Colors.white.withOpacity(0.12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: QrImageView(
              data: session.qrPayload,
              version: QrVersions.auto,
              size: qrSize,
              gapless: true,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Scan to link this desktop',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 20 : 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Open the eSportlyic mobile app and scan this QR code.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh QR'),
          ),
        ],
      ),
    );
  }
}

class _BrandLogo extends StatelessWidget {
  final double size;

  const _BrandLogo({
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppTheme.navyAccent,
        boxShadow: [
          BoxShadow(
            color: AppTheme.navyAccent.withOpacity(0.24),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.asset(
          'assets/icon.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.sports_esports,
            color: Colors.white,
            size: 28,
          ),
        ),
      ),
    );
  }
}
