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
  int _pollCount = 0;
  String _lastStatus = 'idle';
  String _lastNote = 'booting';

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
    if (mounted) {
      setState(() {
        _lastNote = 'metrics changed';
      });
    }
  }

  Future<void> _boot() async {
    if (!mounted) return;

    _pollTimer?.cancel();

    setState(() {
      _loading = true;
      _error = null;
      _paired = false;
      _session = null;
      _pollCount = 0;
      _lastStatus = 'booting';
      _lastNote = 'starting createSession';
    });

    try {
      if (Firebase.apps.isEmpty) {
        setState(() {
          _lastNote = 'waiting for Firebase';
        });

        await Future<void>.delayed(const Duration(milliseconds: 800));

        if (Firebase.apps.isEmpty) {
          throw StateError(
            'Firebase is not initialized. Please refresh the page.',
          );
        }
      }

      setState(() {
        _lastNote = 'calling DesktopPairingService.createSession';
      });

      final session = await DesktopPairingService.instance.createSession();
      if (!mounted) return;

      setState(() {
        _session = session;
        _loading = false;
        _lastStatus = 'session_created';
        _lastNote = 'session ready';
      });

      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _lastStatus = 'boot_error';
        _lastNote = 'boot failed';
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_paired) {
        _pollTimer?.cancel();
        return;
      }

      final current = _session;
      if (current == null) {
        if (mounted) {
          setState(() {
            _lastStatus = 'poll_skipped';
            _lastNote = 'session missing';
          });
        }
        return;
      }

      try {
        if (mounted) {
          setState(() {
            _pollCount++;
            _lastStatus = 'polling';
            _lastNote = 'requesting status';
          });
        }

        final status = await DesktopPairingService.instance.getStatus(
          sessionId: current.sessionId,
          sessionSecret: current.sessionSecret,
        );

        if (!mounted) return;

        setState(() {
          _lastStatus = status.status;
          _lastNote = 'status received';
        });

        if (status.approved ||
            status.status == 'approved' ||
            status.status == 'consumed') {
          _pollTimer?.cancel();
          _paired = true;

          setState(() {
            _lastStatus = 'approved';
            _lastNote = 'pair approved';
          });

          final token = status.firebaseCustomToken.trim();
          if (token.isNotEmpty && Firebase.apps.isNotEmpty) {
            try {
              final auth = FirebaseAuth.instance;
              if (auth.currentUser != null) {
                await auth.signOut();
              }
              await auth.signInWithCustomToken(token);

              if (mounted) {
                setState(() {
                  _lastNote = 'firebase custom token sign-in ok';
                });
              }
            } catch (e) {
              if (mounted) {
                setState(() {
                  _lastNote = 'custom token sign-in skipped: $e';
                });
              }
              debugPrint('Custom token sign-in skipped: $e');
            }
          }

          await WebDesktopSessionStore.save(
            sessionId: current.sessionId,
            sessionSecret: current.sessionSecret,
            pairedUserUid: status.pairedUserUid,
            pairedUserName: status.pairedUserName,
            pairedUserEmail: status.pairedUserEmail,
          );

          if (!mounted) return;

          setState(() {
            _lastNote = 'local session saved; notifying parent';
          });

          widget.onPaired?.call(
            uid: status.pairedUserUid,
            name: status.pairedUserName,
            email: status.pairedUserEmail,
          );
          return;
        }

        if (status.status == 'expired' || status.status == 'rejected') {
          _pollTimer?.cancel();
          if (!mounted) return;
          setState(() {
            _error = 'Session expired. Please refresh to scan again.';
            _lastStatus = status.status;
            _lastNote = 'terminal state';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _lastStatus = 'poll_error';
            _lastNote = e.toString();
          });
        }
        debugPrint('Poll error (will retry): $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final width = size.width;
    final height = size.height;
    final compact = width < 640;
    final stacked = width < 980;
    final brightness = Theme.of(context).brightness;

    final session = _session;

    Widget child;

    if (_loading) {
      child = Center(
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
      );
    } else if (_error != null) {
      child = Center(
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
                      await _boot();
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
    } else if (session == null) {
      child = Center(
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
      );
    } else {
      child = SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final useStacked = stacked || availableWidth < 980;

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1220),
                  child: useStacked
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
                      : Wrap(
                          spacing: 18,
                          runSpacing: 18,
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.start,
                          children: [
                            SizedBox(
                              width: 540,
                              child: _IntroPanel(
                                compact: compact,
                                brightness: brightness,
                              ),
                            ),
                            SizedBox(
                              width: 620,
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
            );
          },
        ),
      );
    }

    return GlassScaffold(
      useBubbles: false,
      body: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _DiagnosticOverlay(
              brightness: brightness,
              values: {
                'width': width.toStringAsFixed(1),
                'height': height.toStringAsFixed(1),
                'compact': '$compact',
                'stacked': '$stacked',
                'loading': '$_loading',
                'paired': '$_paired',
                'hasError': '${_error != null}',
                'hasSession': '${_session != null}',
                'firebaseApps': '${Firebase.apps.length}',
                'pollCount': '$_pollCount',
                'lastStatus': _lastStatus,
                'lastNote': _lastNote,
                'sessionId': session?.sessionId ?? '',
                'sessionSecret': session?.sessionSecret ?? '',
                'qrPayloadLen': session == null ? '0' : '${session.qrPayload.length}',
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticOverlay extends StatelessWidget {
  final Brightness brightness;
  final Map<String, String> values;

  const _DiagnosticOverlay({
    required this.brightness,
    required this.values,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Glass(
          borderRadius: 18,
          padding: const EdgeInsets.all(12),
          fill: brightness == Brightness.dark
              ? const Color(0xE61A2230)
              : const Color(0xEFFFFFFF),
          borderColor: AppTheme.cardBorder(brightness),
          child: DefaultTextStyle(
            style: TextStyle(
              color: AppTheme.primaryText(brightness),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            child: Wrap(
              spacing: 14,
              runSpacing: 8,
              children: values.entries.map((entry) {
                return RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: AppTheme.primaryText(brightness),
                      fontSize: 12,
                    ),
                    children: [
                      TextSpan(
                        text: '${entry.key}: ',
                        style: TextStyle(
                          color: AppTheme.limeAccentDark,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      TextSpan(
                        text: entry.value.isEmpty ? '—' : entry.value,
                        style: TextStyle(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
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

  const _IntroPanel({
    required this.compact,
    required this.brightness,
  });

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
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
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
    final qrSize = compact ? 220.0 : (width < 1200 ? 260.0 : 300.0);

    return Glass(
      borderRadius: 28,
      padding: EdgeInsets.all(compact ? 18 : 24),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
            child: session.qrPayload.trim().isEmpty
                ? const SizedBox(
                    width: 260,
                    height: 260,
                    child: Center(
                      child: Text(
                        'QR payload empty',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                  )
                : QrImageView(
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
          const SizedBox(height: 12),
          SelectableText(
            'payload: ${session.qrPayload}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              fontSize: 11,
              height: 1.35,
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
