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

    return AlertDialog(
      backgroundColor: const Color(0xFF000428),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      title: Text(
        l10n.tr('generate_knockout_dialog_title'),
        style: const TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.tr('generate_knockout_dialog_qualified_teams_intro'),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 8,
              children: qualifiedTeams
                  .map(
                    (t) => Chip(
                      label: Text(t, style: const TextStyle(fontSize: 10)),
                      backgroundColor: Colors.blueAccent.withOpacity(0.2),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.tr('generate_knockout_dialog_warning'),
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.tr('generate_knockout_dialog_cancel').toUpperCase()),
        ),
        ElevatedButton(
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
