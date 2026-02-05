import 'package:flutter/material.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/widgets/glass_scaffold.dart';

class BootstrapScreen extends StatelessWidget {
  const BootstrapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final onBg = theme.colorScheme.onBackground;

    return GlassScaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              l10n.authBootstrapLoading,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: onBg.withOpacity(0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
