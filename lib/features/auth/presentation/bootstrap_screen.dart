import 'package:flutter/material.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/widgets/glass_scaffold.dart';

class BootstrapScreen extends StatelessWidget {
  const BootstrapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final onBg = Theme.of(context).colorScheme.onBackground;

    return GlassScaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.cyanAccent),
            const SizedBox(height: 12),
            Text(
              l10n.authBootstrapLoading,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: onBg.withOpacity(0.75)),
            ),
          ],
        ),
      ),
    );
  }
}
