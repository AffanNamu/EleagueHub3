import 'package:flutter/material.dart';

import '../locale/app_localizations.dart';
import 'glass.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
            l10n.tr('offline_banner_message'),
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
