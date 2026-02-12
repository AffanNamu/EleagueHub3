import 'package:flutter/material.dart';

import 'glass.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // ONLINE-ONLY: do not promise "sync later". This is a network status indicator only.
    const message = "You're offline. Please check your connection.";

    return Glass(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      borderRadius: 0,
      enableBorder: false,
      fill: colorScheme.error.withOpacity(0.85),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 16,
            color: colorScheme.onError,
          ),
          const SizedBox(width: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onError,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
