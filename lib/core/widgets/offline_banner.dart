import 'package:flutter/material.dart';

import 'glass.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    const message = "You're offline. Please check your connection.";

    return Glass(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      borderRadius: 0,
      fill: colorScheme.error.withOpacity(0.95),
      border: false,
      boxShadow: const [],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            size: 16,
            color: colorScheme.onError,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onError,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
