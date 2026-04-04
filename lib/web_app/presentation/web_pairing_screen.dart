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

        if (status.approved || status.status == 'approved' || status.status == 'consumed') {
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
          setState(() {
            _error = 'This desktop session expired. Please refresh and scan again.';
          });
        }
      } catch (_) {}
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
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF111B21),
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              flex: 6,
              child: Container(
                color: const Color(0xFF202C33),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: _buildLeftPanel(theme),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 7,
              child: Container(
                color: const Color(0xFF0B141A),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: _buildRightPanel(theme),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftPanel(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
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
            Text(
              'EleagueHub Web',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          'Use EleagueHub on your computer',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '1. Open EleagueHub on your phone\n'
          '2. Go to the QR scanner\n'
          '3. Scan this code to link your desktop',
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white.withOpacity(0.82),
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 26),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline,
                color: Colors.white.withOpacity(0.85),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your phone stays the primary device. This desktop session is linked securely through your mobile app.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withOpacity(0.72),
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRightPanel(ThemeData theme) {
    if (_loading) {
      return _buildCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 18),
            Text(
              'Preparing desktop session...',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return _buildCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 42),
            const SizedBox(height: 14),
            Text(
              'Could not start desktop pairing',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withOpacity(0.74),
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
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
      );
    }

    final session = _session;
    if (session == null) return const SizedBox.shrink();

    return _buildCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          Text(
            'Scan to link this desktop',
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Open the EleagueHub mobile app and scan this QR code.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withOpacity(0.72),
              height: 1.45,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          TextButton.icon(
            onPressed: () async {
              await WebDesktopSessionStore.clear();
              _boot();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh QR'),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF202C33),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}
