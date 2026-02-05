import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';

class LiveListScreen extends StatelessWidget {
  const LiveListScreen({super.key});

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
                        onPressed: () => context.push('/live/join'),
                        icon: const Icon(Icons.login),
                        label: Text(l10n.tr('live_list_join_match_button')),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final matchIdCtrl = TextEditingController();
                          final portCtrl = TextEditingController(text: '8765');

                          try {
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
                            if (matchId.isEmpty) return;

                            // Opens host view; you can also navigate here from match detail screen in your app.
                            if (context.mounted) {
                              context.push(
                                '/live/view/$matchId',
                                extra: {
                                  'isHost': true,
                                  'port': port,
                                },
                              );
                            }
                          } finally {
                            matchIdCtrl.dispose();
                            portCtrl.dispose();
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
