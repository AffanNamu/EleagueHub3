import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';

class LiveListScreen extends StatelessWidget {
  const LiveListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('live_list_appbar_title'))),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () => context.push('/live/join'),
              child: Text(l10n.tr('live_list_join_match_button')),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () async {
                final matchIdCtrl = TextEditingController();
                final portCtrl = TextEditingController(text: '8765');

                try {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(l10n.tr('live_list_host_dialog_title')),
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
                    ),
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
              child: Text(l10n.tr('live_list_host_match_button')),
            ),
          ],
        ),
      ),
    );
  }
}
