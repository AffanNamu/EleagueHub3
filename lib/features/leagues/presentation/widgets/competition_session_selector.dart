// lib/features/leagues/presentation/widgets/competition_session_selector.dart

import 'package:flutter/material.dart';

import '../../../../core/locale/app_localizations.dart';
import '../../../../core/theme/app_theme.dart';
import '../../logic/competition_session_options.dart';

/// A chip-row session picker, matching this app's existing format/privacy
/// ChoiceChip pattern (see league_create_wizard.dart's own formatChip) so it
/// looks native wherever it's dropped into a creation or edit screen.
///
/// Shown as a "Session" label followed by a row of dynamically generated
/// options (CompetitionSessionOptions.generate) plus a "Custom" chip that
/// opens a small dialog for a free-text value. The organizer's selection is
/// always final -- this widget never writes anywhere itself, it only
/// reports the chosen String via [onChanged]. The caller decides what the
/// initial [value] is (a saved League's existing season when editing, or
/// CompetitionSessionOptions.suggestedDefault() when creating).
class CompetitionSessionSelector extends StatelessWidget {
  const CompetitionSessionSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  Future<void> _pickCustom(BuildContext context, List<String> options) async {
    final l10n = context.l10n;
    final isCustomValue = !options.contains(value);
    final controller = TextEditingController(text: isCustomValue ? value : '');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.tr('competition_session_custom_title')),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: CompetitionSessionOptions.maxLength,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: l10n.tr('competition_session_custom_hint'),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.tr('common_cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: Text(l10n.tr('common_save')),
            ),
          ],
        );
      },
    );

    if (result == null) return;
    final normalized = CompetitionSessionOptions.normalizeCustom(result);
    if (normalized == null) return;
    onChanged(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final options = CompetitionSessionOptions.generate();
    final isCustomValue = value.trim().isNotEmpty && !options.contains(value);

    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback? onTap,
    }) {
      return ChoiceChip(
        selected: selected,
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        selectedColor: AppTheme.limeAccent,
        backgroundColor: AppTheme.tabInactiveBackground(brightness),
        side: BorderSide(
          color: selected ? AppTheme.limeAccentDark : AppTheme.cardBorder(brightness),
        ),
        labelStyle: TextStyle(
          color: selected ? AppTheme.darkText : AppTheme.tabInactiveText(brightness),
          fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
        ),
        onSelected: onTap == null ? null : (v) { if (v) onTap(); },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.tr('competition_session_label'),
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w900,
            color: AppTheme.primaryText(brightness),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              chip(
                label: option,
                selected: !isCustomValue && value == option,
                onTap: enabled ? () => onChanged(option) : null,
              ),
            chip(
              label: isCustomValue
                  ? value
                  : l10n.tr('competition_session_custom_chip'),
              selected: isCustomValue,
              onTap: enabled ? () => _pickCustom(context, options) : null,
            ),
          ],
        ),
      ],
    );
  }
}
