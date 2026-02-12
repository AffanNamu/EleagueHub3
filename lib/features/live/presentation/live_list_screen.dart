import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';

class LiveListScreen extends StatefulWidget {
  const LiveListScreen({super.key});

  @override
  State<LiveListScreen> createState() => _LiveListScreenState();
}

class _LiveListScreenState extends State<LiveListScreen> {
  bool _busy = false;

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _ensureSignedInAndOnline() async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      _showSnack('Please sign in and try again.');
      if (mounted) context.go('/login');
      return false;
    }

    await ConnectivityService.instance.initialize();
    final ok = await ConnectivityService.instance.recheckConnection(timeout: const Duration(seconds: 4));
    if (!ok) {
      _showSnack(UserFriendlyError.toMessage(SocketException('offline')));
      return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('live_list_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Glass(
                borderRadius: 24,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.tr('live_list_appbar_title'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                setState(() => _busy = true);
                                try {
                                  final ok = await _ensureSignedInAndOnline();
                                  if (!ok) return;
                                  if (!mounted) return;
                                  context.push('/live/join');
                                } catch (e) {
                                  _showSnack(UserFriendlyError.toMessage(e));
                                } finally {
                                  if (mounted) setState(() => _busy = false);
                                }
                              },
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.login),
                        label: Text(l10n.tr('live_list_join_match_button')),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                setState(() => _busy = true);

                                final matchIdCtrl = TextEditingController();
                                final portCtrl = TextEditingController(text: '8765');

                                try {
                                  final okOnline = await _ensureSignedInAndOnline();
                                  if (!okOnline) return;
                                  if (!mounted) return;

                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) {
                                      final dialogTheme = Theme.of(ctx);
                                      final dialogCs = dialogTheme.colorScheme;

                                      return AlertDialog(
                                        backgroundColor: dialogCs.surface,
                                        title: Text(
                                          l10n.tr('live_list_host_dialog_title'),
                                          style: TextStyle(
                                            color: dialogCs.onSurface,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TextField(
                                              controller: matchIdCtrl,
                                              decoration: InputDecoration(
                                                labelText: l10n.tr('live_list_host_dialog_live_match_id_label'),
                                                hintText: l10n.tr('live_list_host_dialog_live_match_id_hint'),
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            TextField(
                                              controller: portCtrl,
                                              keyboardType: TextInputType.number,
                                              decoration: InputDecoration(
                                                labelText: l10n.tr('live_list_host_dialog_port_label'),
                                                hintText: l10n.tr('live_list_host_dialog_port_hint'),
                                              ),
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: Text(l10n.tr('common_cancel')),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: Text(l10n.tr('live_list_host_dialog_start')),
                                          ),
                                        ],
                                      );
                                    },
                                  );

                                  if (ok != true) return;

                                  final matchId = matchIdCtrl.text.trim();
                                  final port = int.tryParse(portCtrl.text.trim()) ?? 8765;
                                  if (matchId.isEmpty) {
                                    _showSnack('Please enter a valid match ID.');
                                    return;
                                  }

                                  if (!mounted) return;

                                  // Port is legacy for older LAN flows; LiveViewScreen ignores it online.
                                  context.push(
                                    '/live/view/$matchId',
                                    extra: {
                                      'isHost': true,
                                      'port': port,
                                    },
                                  );
                                } catch (e) {
                                  _showSnack(UserFriendlyError.toMessage(e));
                                } finally {
                                  matchIdCtrl.dispose();
                                  portCtrl.dispose();
                                  if (mounted) setState(() => _busy = false);
                                }
                              },
                        icon: const Icon(Icons.cast),
                        label: Text(
                          l10n.tr('live_list_host_match_button'),
                          style: TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.primary,
                          side: BorderSide(color: cs.primary),
                        ),
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
