import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/desktop/desktop_pairing_models.dart';
import '../../core/services/desktop/desktop_pairing_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/glass_scaffold.dart';
import 'web_desktop_session_store.dart';

class WebPairingScreen extends StatefulWidget {
  /// Called when phone successfully scans and approves.
  /// Parent swaps to shell without Navigator push.
  final void Function({
    required String uid,
    required String name,
    required String email,
  })? onPaired;

  const WebPairingScreen({super.key, this.onPaired});

  @override
  State<WebPairingScreen> createState() => _WebPairingScreenState();
}

class _WebPairingScreenState extends State<WebPairingScreen>
    with WidgetsBindingObserver {
  DesktopPairingSession? _session;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  bool _paired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  Future<void> _boot() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _paired = false;
    });

    try {
      // Wait for Firebase
      if (Firebase.apps.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (Firebase.apps.isEmpty) {
          throw StateError(
              'Firebase is not initialized. Please refresh the page.');
        }
      }

      final session =
          await DesktopPairingService.instance.createSession();
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
    _pollTimer =
        Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_paired) {
        _pollTimer?.cancel();
        return;
      }

      final current = _session;
      if (current == null) return;

      try {
        final status =
            await DesktopPairingService.instance.getStatus(
          sessionId: current.sessionId,
          sessionSecret: current.sessionSecret,
        );

        if (!mounted) return;

        if (status.approved ||
            status.status == 'approved' ||
            status.status == 'consumed') {
          _pollTimer?.cancel();
          _paired = true;

          // Try Firebase custom token sign-in
          final token = status.firebaseCustomToken.trim();
          if (token.isNotEmpty && Firebase.apps.isNotEmpty) {
            try {
              final auth = FirebaseAuth.instance;
              if (auth.currentUser != null) await auth.signOut();
              await auth.signInWithCustomToken(token);
            } catch (e) {
              debugPrint('Custom token sign-in skipped: $e');
            }
          }

          // Save to localStorage
          await WebDesktopSessionStore.save(
            sessionId: current.sessionId,
            sessionSecret: current.sessionSecret,
            pairedUserUid: status.pairedUserUid,
            pairedUserName: status.pairedUserName,
            pairedUserEmail: status.pairedUserEmail,
          );

          if (!mounted) return;

          // ── Notify parent to swap screen (no Navigator.push) ──────
          widget.onPaired?.call(
            uid: status.pairedUserUid,
            name: status.pairedUserName,
            email: status.pairedUserEmail,
          );
          return;
        }

        if (status.status == 'expired' ||
            status.status == 'rejected') {
          _pollTimer?.cancel();
          if (!mounted) return;
          setState(() {
            _error =
                'Session expired. Please refresh to scan again.';
          });
        }
      } catch (e) {
        debugPrint('Poll error (will retry): $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final compact = width < 640;
    final stacked = width < 980;
    final brightness = Theme.of(context).brightness;

    if (_loading) {
      return GlassScaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _InfoCard(
                title: 'Preparing desktop session...',
                subtitle:
                    'Please wait while we generate your eSportlyic Web QR login.',
                brightness: brightness,
                child: const Padding(
                  padding: EdgeInsets.only(top: 18),
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppTheme.limeAccentDark,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return GlassScaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _InfoCard(
                title: 'Could not start desktop pairing',
                subtitle: _error!,
                brightness: brightness,
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.limeAccent,
                        foregroundColor: AppTheme.darkText,
                      ),
                      onPressed: () async {
                        _paired = false;
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
        ),
      );
    }

    final session = _session;
    if (session == null) {
      return GlassScaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _InfoCard(
                title: 'No session available',
                subtitle: 'Tap refresh to create a new QR session.',
                brightness: brightness,
                child: Column(
                  children: [
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.limeAccent,
                        foregroundColor: AppTheme.darkText,
                      ),
                      onPressed: _boot,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GlassScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1220),
              child: stacked
                  ? Column(
                      children: [
                        _QrPanel(
                          session: session,
                          onRefresh: _boot,
                          compact: compact,
                          brightness: brightness,
                        ),
                        const SizedBox(height: 16),
                        _IntroPanel(
                          compact: compact,
                          brightness: brightness,
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: _IntroPanel(
                            compact: compact,
                            brightness: brightness,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          flex: 7,
                          child: _QrPanel(
                            session: session,
                            onRefresh: _boot,
                            compact: compact,
                            brightness: brightness,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Brightness brightness;

  const _InfoCard({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 28,
      padding: const EdgeInsets.all(24),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.primaryText(brightness),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
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
  final Brightness brightness;
  const _IntroPanel({required this.compact, required this.brightness});

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 28,
      padding: EdgeInsets.all(compact ? 18 : 24),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
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
                  style:
                      Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: AppTheme.primaryText(brightness),
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
            style:
                Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppTheme.primaryText(brightness),
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
                  color: AppTheme.secondaryText(brightness),
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 18 : 22,
                ),
          ),
          const SizedBox(height: 18),
          Glass(
            borderRadius: 22,
            padding: const EdgeInsets.all(16),
            fill: AppTheme.searchBackground(brightness),
            borderColor: AppTheme.searchOutline(brightness),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  color: AppTheme.limeAccentDark,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your phone stays the primary device. '
                    'This desktop session is linked securely '
                    'through your mobile app.',
                    style: TextStyle(
                      color: AppTheme.secondaryText(brightness),
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
  final Brightness brightness;

  const _QrPanel({
    required this.session,
    required this.onRefresh,
    required this.compact,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final qrSize =
        compact ? 220.0 : (width < 1200 ? 260.0 : 300.0);

    return Glass(
      borderRadius: 28,
      padding: EdgeInsets.all(compact ? 18 : 24),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
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
              color: AppTheme.primaryText(brightness),
              fontSize: compact ? 20 : 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Open the eSportlyic mobile app and scan this QR code.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.limeAccent,
              foregroundColor: AppTheme.darkText,
            ),
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
  const _BrandLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppTheme.limeAccent,
        boxShadow: [
          BoxShadow(
            color: AppTheme.limeAccentDark.withOpacity(0.24),
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
            color: AppTheme.darkText,
            size: 28,
          ),
        ),
      ),
    );
  }
}
