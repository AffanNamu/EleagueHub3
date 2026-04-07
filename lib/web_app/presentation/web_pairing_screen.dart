import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../../core/services/desktop/desktop_pairing_models.dart';
import '../../core/services/desktop/desktop_pairing_service.dart';
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

class _WebPairingScreenState extends State<WebPairingScreen> {
  DesktopPairingSession? _session;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  bool _paired = false;

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
    _pollTimer?.cancel();

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _session = null;
      _paired = false;
    });

    try {
      if (Firebase.apps.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }

      if (Firebase.apps.isEmpty) {
        throw StateError('Firebase is not initialized. Please refresh the page.');
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
      if (_paired) {
        _pollTimer?.cancel();
        return;
      }

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
          _paired = true;

          final token = status.firebaseCustomToken.trim();
          if (token.isNotEmpty && Firebase.apps.isNotEmpty) {
            try {
              final auth = FirebaseAuth.instance;
              if (auth.currentUser != null) {
                await auth.signOut();
              }
              await auth.signInWithCustomToken(token);
            } catch (e) {
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
          });
        }
      } catch (e) {
        debugPrint('Poll error (will retry): $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 980;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1220),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _loading
                  ? const _PlainStatusCard(
                      title: 'Preparing desktop session...',
                      subtitle:
                          'Please wait while we generate your eSportlyic Web login session.',
                      child: Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _error != null
                      ? _PlainStatusCard(
                          title: 'Could not start desktop pairing',
                          subtitle: _error!,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: FilledButton(
                              onPressed: _boot,
                              child: const Text('Try again'),
                            ),
                          ),
                        )
                      : _session == null
                          ? _PlainStatusCard(
                              title: 'No session available',
                              subtitle: 'Tap refresh to create a new session.',
                              child: Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: FilledButton(
                                  onPressed: _boot,
                                  child: const Text('Refresh'),
                                ),
                              ),
                            )
                          : wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _PlainIntroCard(
                                        session: _session!,
                                        onRefresh: _boot,
                                      ),
                                    ),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      child: _PlainQrCard(
                                        session: _session!,
                                        onRefresh: _boot,
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _PlainQrCard(
                                      session: _session!,
                                      onRefresh: _boot,
                                    ),
                                    const SizedBox(height: 16),
                                    _PlainIntroCard(
                                      session: _session!,
                                      onRefresh: _boot,
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

class _PlainStatusCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _PlainStatusCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black54,
                height: 1.4,
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _PlainIntroCard extends StatelessWidget {
  final DesktopPairingSession session;
  final VoidCallback onRefresh;

  const _PlainIntroCard({
    required this.session,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'eSportlyic Web',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Use eSportlyic on your computer',
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '1. Open eSportlyic on your phone\n'
              '2. Go to the QR scanner\n'
              '3. Scan the pairing payload shown on this page',
              style: TextStyle(
                fontSize: 18,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFFF2F4F7),
              child: const Text(
                'This temporary production-safe fallback uses a plain layout while web rendering issues are isolated.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlainQrCard extends StatelessWidget {
  final DesktopPairingSession session;
  final VoidCallback onRefresh;

  const _PlainQrCard({
    required this.session,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              'Desktop pairing payload',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFFF8F9FB),
              child: SelectableText(
                session.qrPayload,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              'sessionId: ${session.sessionId}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            SelectableText(
              'sessionSecret: ${session.sessionSecret}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onRefresh,
              child: const Text('Refresh session'),
            ),
          ],
        ),
      ),
    );
  }
}
