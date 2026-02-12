import 'dart:async';

import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../widgets/glass.dart';
import '../widgets/glass_scaffold.dart';

/// ONLINE-ONLY MIGRATION:
/// The legacy app had an offline-first sync engine with debug tooling.
/// In online-only mode there is no local queue and no background sync.
///
/// This screen is retained as a diagnostics screen:
/// - shows connectivity status
/// - allows manual connectivity recheck
class SyncDebugScreen extends StatelessWidget {
  const SyncDebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Connection Diagnostics'),
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
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: ConnectivityService.instance.isConnected,
                    builder: (context, online, _) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                            size: 44,
                            color: online ? cs.primary : cs.error,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            online ? 'You are online' : 'You are offline',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            online
                                ? 'All data is loaded live from the server.'
                                : 'Some actions may not work until your connection is restored.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurface.withOpacity(0.70),
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                          ),
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: () async {
                              try {
                                await ConnectivityService.instance
                                    .recheckConnection(timeout: const Duration(seconds: 5))
                                    .timeout(const Duration(seconds: 6));
                              } catch (_) {
                                // ConnectivityService already falls back to offline safely.
                              }
                            },
                            child: const Text('Recheck connection'),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
