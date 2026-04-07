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
  int _pollCount = 0;
  String _lastStatus = 'idle';
  String _lastNote = 'init';

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
      _pollCount = 0;
      _lastStatus = 'booting';
      _lastNote = 'starting';
    });

    try {
      if (Firebase.apps.isEmpty) {
        setState(() {
          _lastNote = 'Firebase.apps is empty, waiting';
        });
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }

      if (Firebase.apps.isEmpty) {
        throw StateError('Firebase is not initialized');
      }

      setState(() {
        _lastNote = 'calling createSession';
      });

      final session = await DesktopPairingService.instance.createSession();

      if (!mounted) return;
      setState(() {
        _session = session;
        _loading = false;
        _lastStatus = 'session_created';
        _lastNote = 'createSession ok';
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
        if (!mounted) return;
        setState(() {
          _lastStatus = 'poll_skipped';
          _lastNote = 'session null';
        });
        return;
      }

      try {
        if (!mounted) return;
        setState(() {
          _pollCount++;
          _lastStatus = 'polling';
          _lastNote = 'calling getStatus';
        });

        final status = await DesktopPairingService.instance.getStatus(
          sessionId: current.sessionId,
          sessionSecret: current.sessionSecret,
        );

        if (!mounted) return;
        setState(() {
          _lastStatus = status.status;
          _lastNote = 'getStatus ok';
        });

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
              if (mounted) {
                setState(() {
                  _lastNote = 'custom token sign-in ok';
                });
              }
            } catch (e) {
              if (mounted) {
                setState(() {
                  _lastNote = 'custom token sign-in skipped: $e';
                });
              }
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
            _lastStatus = 'approved';
            _lastNote = 'saved locally, notifying parent';
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
            _error = 'Session expired or rejected';
            _lastStatus = status.status;
            _lastNote = 'terminal state';
          });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _lastStatus = 'poll_error';
          _lastNote = e.toString();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final session = _session;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black,
              child: const Text(
                'WEB PAIRING DIAGNOSTIC',
                style: TextStyle(
                  color: Colors.lime,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText('width: ${media.size.width}'),
            SelectableText('height: ${media.size.height}'),
            SelectableText('loading: $_loading'),
            SelectableText('paired: $_paired'),
            SelectableText('error: ${_error ?? 'none'}'),
            SelectableText('firebaseApps: ${Firebase.apps.length}'),
            SelectableText('pollCount: $_pollCount'),
            SelectableText('lastStatus: $_lastStatus'),
            SelectableText('lastNote: $_lastNote'),
            SelectableText('hasSession: ${session != null}'),
            SelectableText('sessionId: ${session?.sessionId ?? ''}'),
            SelectableText('sessionSecret: ${session?.sessionSecret ?? ''}'),
            SelectableText('qrPayload: ${session?.qrPayload ?? ''}'),
            const SizedBox(height: 20),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _boot,
                  child: const Text('Refresh session'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () async {
                    await WebDesktopSessionStore.clear();
                    if (!mounted) return;
                    setState(() {
                      _lastNote = 'local session cleared';
                    });
                  },
                  child: const Text('Clear local session'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade200,
              child: Text(
                _loading
                    ? 'STATE: LOADING'
                    : (_error != null
                        ? 'STATE: ERROR'
                        : (session == null ? 'STATE: NO SESSION' : 'STATE: SESSION READY')),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
