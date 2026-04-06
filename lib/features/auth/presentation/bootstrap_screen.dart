import 'package:flutter/material.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_scaffold.dart';

class BootstrapScreen extends StatelessWidget {
  const BootstrapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return GlassScaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.limeAccentDark),
            const SizedBox(height: 12),
            Text(
              l10n.authBootstrapLoading,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.secondaryText(brightness),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
