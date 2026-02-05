import 'package:flutter/material.dart';

import '../core/locale/app_localizations.dart';

/// Returns a bool via Navigator.pop:
/// - true  => user confirmed "START KNOCKOUTS"
/// - false => user cancelled (or dismissed)
class GenerateKnockoutDialog extends StatelessWidget {
  final List<String> qualifiedTeams;

  const GenerateKnockoutDialog({super.key, required this.qualifiedTeams});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: cs.onSurface.withOpacity(0.12)),
      ),
      title: Text(
        l10n.tr('generate_knockout_dialog_title'),
        style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.tr('generate_knockout_dialog_qualified_teams_intro'),
              style: TextStyle(color: cs.onSurface.withOpacity(0.72), fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: qualifiedTeams
                  .map(
                    (t) => Chip(
                      label: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                      backgroundColor: cs.primary.withOpacity(0.12),
                      side: BorderSide(color: cs.primary.withOpacity(0.18)),
                      labelStyle: TextStyle(color: cs.onSurface),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.tr('generate_knockout_dialog_warning'),
              style: const TextStyle(
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
          child: Text(l10n.tr('generate_knockout_dialog_cancel').toUpperCase()),
        ),
        FilledButton(
          onPressed: () {
            // Let the caller trigger bracket generation based on the returned result.
            Navigator.pop(context, true);
          },
          child: Text(l10n.tr('generate_knockout_dialog_start_knockouts').toUpperCase()),
        ),
      ],
    );
  }
}
