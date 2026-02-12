import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/services/connectivity_service.dart';

class SyncStatusCard extends StatelessWidget {
  const SyncStatusCard({super.key});

  String _friendlyMessageForError(Object error) {
    if (error is SocketException) {
      return 'Your network appears to be offline. Please check your connection and try again.';
    }
    if (error is TimeoutException) {
      return 'Your internet connection seems unstable. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final onlineListenable = ConnectivityService.instance.isConnected;

    return ValueListenableBuilder<bool>(
      valueListenable: onlineListenable,
      builder: (context, online, _) {
        final title = online ? 'Online' : 'Offline';
        final subtitle = online
            ? 'You are connected. All actions use live cloud data.'
            : 'You are offline. Please check your connection to continue.';

        return Card(
          color: Colors.white.withOpacity(0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ListTile(
            leading: Icon(
              online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: online ? Colors.cyanAccent : Colors.redAccent,
            ),
            title: Text(
              title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              subtitle,
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: IconButton(
              tooltip: 'Recheck connection',
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () async {
                try {
                  final ok = await ConnectivityService.instance
                      .recheckConnection(timeout: const Duration(seconds: 5))
                      .timeout(const Duration(seconds: 6));

                  if (!context.mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok ? 'Connected.' : 'You appear to be offline. Please check your connection.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_friendlyMessageForError(e is Object ? e : Exception('unknown'))),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }
}
