import 'package:flutter/material.dart';

import '../core/locale/app_localizations.dart';
import '../core/theme/app_theme.dart';

/// Returns a bool via Navigator.pop:
/// - true  => user confirmed "START KNOCKOUTS"
/// - false => user cancelled
class GenerateKnockoutDialog extends StatelessWidget {
  final List<String> qualifiedTeams;

  const GenerateKnockoutDialog({super.key, required this.qualifiedTeams});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return AlertDialog(
      backgroundColor: AppTheme.cardColor(brightness),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppTheme.cardBorder(brightness)),
      ),
      title: Text(
        l10n.tr('generate_knockout_dialog_title'),
        style: TextStyle(
          color: AppTheme.primaryText(brightness),
          fontWeight: FontWeight.w900,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.tr('generate_knockout_dialog_qualified_teams_intro'),
              style: TextStyle(
                color: AppTheme.secondaryText(brightness),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: qualifiedTeams
                  .map(
                    (t) => Chip(
                      label: Text(
                        t,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryText(brightness),
                        ),
                      ),
                      backgroundColor: brightness == Brightness.dark
                          ? AppTheme.limeAccentDark.withOpacity(0.16)
                          : const Color(0xFFECFCCB),
                      side: BorderSide(
                        color: brightness == Brightness.dark
                            ? AppTheme.limeAccentDark.withOpacity(0.24)
                            : const Color(0xFFD9F99D),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              'This action will generate the knockout bracket.',
              style: TextStyle(
                color: Color(0xFFF59E0B),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            l10n.tr('generate_knockout_dialog_cancel').toUpperCase(),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.limeAccent,
            foregroundColor: AppTheme.darkText,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            l10n.tr('generate_knockout_dialog_start_knockouts').toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}
