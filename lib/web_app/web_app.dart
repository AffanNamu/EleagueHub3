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
      builder: (context, child) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

class _WebRootGate extends StatefulWidget {
  const _WebRootGate();

  @override
  State<_WebRootGate> createState() => _WebRootGateState();
}

class _WebRootGateState extends State<_WebRootGate> {
  bool _checking = true;
  Map<String, String>? _savedSession;
  String _status = 'init';
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (!mounted) return;
    setState(() {
      _status = 'loading local session';
      _checking = true;
      _error = null;
    });

    try {
      final saved = await WebDesktopSessionStore.load();
      if (!mounted) return;
      setState(() {
        _savedSession = saved;
        _checking = false;
        _status = 'local session loaded';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = e.toString();
        _status = 'load failed';
      });
    }
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
      _status = 'paired callback received';
    });
  }

  void _onUnlink() {
    WebDesktopSessionStore.clear();
    if (!mounted) return;
    setState(() {
      _savedSession = null;
      _checking = false;
      _status = 'unlinked';
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _savedSession;
    final uid = (session?['pairedUserUid'] ?? '').trim();
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.all(12),
              child: const Text(
                'ROOT DIAGNOSTIC',
                style: TextStyle(
                  color: Colors.lime,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SelectableText('width: $width'),
                  SelectableText('height: $height'),
                  SelectableText('checking: $_checking'),
                  SelectableText('status: $_status'),
                  SelectableText('error: ${_error ?? 'none'}'),
                  SelectableText('hasSavedSession: ${session != null}'),
                  SelectableText('uid: $uid'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton(
                        onPressed: _check,
                        child: const Text('Reload gate'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          await WebDesktopSessionStore.clear();
                          if (!mounted) return;
                          setState(() {
                            _savedSession = null;
                            _status = 'local session cleared';
                          });
                        },
                        child: const Text('Clear local session'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => WebPairingScreen(
                                onPaired: _onPaired,
                              ),
                            ),
                          );
                        },
                        child: const Text('Open pairing screen'),
                      ),
                      ElevatedButton(
                        onPressed: uid.isEmpty
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => WebDesktopShellScreen(
                                      pairedUserUid: uid,
                                      pairedUserName:
                                          session?['pairedUserName'] ?? '',
                                      pairedUserEmail:
                                          session?['pairedUserEmail'] ?? '',
                                      onUnlink: _onUnlink,
                                    ),
                                  ),
                                );
                              },
                        child: const Text('Open shell screen'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.blue.shade50,
                    child: Text(
                      _checking
                          ? 'GATE STATE: CHECKING'
                          : (uid.isNotEmpty
                              ? 'GATE STATE: HAS SAVED SESSION'
                              : 'GATE STATE: NO SAVED SESSION'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_checking)
                    const Text('Child screen not mounted yet.')
                  else if (uid.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.green.shade50,
                      child: const Text(
                        'A saved session exists. Use "Open shell screen" to test shell rendering directly.',
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.orange.shade50,
                      child: const Text(
                        'No saved session. Use "Open pairing screen" to test pairing rendering directly.',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
