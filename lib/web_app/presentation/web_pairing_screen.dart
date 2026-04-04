import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/desktop/desktop_pairing_models.dart';
import '../../core/services/desktop/desktop_pairing_service.dart';
import 'web_desktop_session_store.dart';
import 'web_desktop_shell_screen.dart';

class WebPairingScreen extends StatefulWidget {
  const WebPairingScreen({super.key});

  @override
  State<WebPairingScreen> createState() => _WebPairingScreenState();
}

class _WebPairingScreenState extends State<WebPairingScreen> {
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
    if (_loading) {
      return _PageScaffold(
        child: _InfoCard(
          title: 'Preparing desktop session...',
          subtitle: 'Please wait while we generate your QR login.',
          child: const Padding(
            padding: EdgeInsets.only(top: 18),
            child: SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return _PageScaffold(
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
      );
    }

    final session = _session;
    if (session == null) {
      return _PageScaffold(
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
      );
    }

    return _PageScaffold(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 900;

          final leftPanel = _LeftPanel(
            title: 'Use EleagueHub on your computer',
            body:
                '1. Open EleagueHub on your phone\n'
                '2. Go to the QR scanner\n'
                '3. Scan this code to link your desktop',
          );

          final rightPanel = _QrPanel(
            session: session,
            onRefresh: _boot,
          );

          if (narrow) {
            return Column(
              children: [
                leftPanel,
                const SizedBox(height: 16),
                rightPanel,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: leftPanel),
              const SizedBox(width: 16),
              Expanded(flex: 7, child: rightPanel),
            ],
          );
        },
      ),
    );
  }
}

class _PageScaffold extends StatelessWidget {
  final Widget child;

  const _PageScaffold({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111B21),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: child,
            ),
          ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF202C33),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              height: 1.45,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _LeftPanel extends StatelessWidget {
  final String title;
  final String body;

  const _LeftPanel({
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF202C33),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.sports_esports,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'EleagueHub Web',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
          ),
          const SizedBox(height: 14),
          Text(
            body,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withOpacity(0.82),
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Text(
              'Your phone stays the primary device. This desktop session is linked securely through your mobile app.',
              style: TextStyle(
                color: Colors.white.withOpacity(0.72),
                height: 1.45,
              ),
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

  const _QrPanel({
    required this.session,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0B141A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: session.qrPayload,
              version: QrVersions.auto,
              size: 260,
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
          const Text(
            'Scan to link this desktop',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Open the EleagueHub mobile app and scan this QR code.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh QR'),
          ),
        ],
      ),
    );
  }
}
