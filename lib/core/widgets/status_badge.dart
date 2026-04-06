import 'package:flutter/material.dart';

import '../locale/app_localizations.dart';
import '../theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge(
    this.status, {
    super.key,
  });

  final String status;

  String _localizedStatus(BuildContext context, String raw) {
    final l10n = context.l10n;
    final s = raw.trim().toLowerCase();

    switch (s) {
      case 'pending':
        return l10n.tr('admin_knockout_status_pending');
      case 'completed':
        return l10n.tr('admin_knockout_status_completed');
      case 'live':
        return l10n.tr('league_space_live_badge');
      case 'ended':
        return l10n.tr('league_space_ended_badge');
      default:
        return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final backgroundColor = AppTheme.statusColor(status, theme.brightness);
    final bgBrightness = ThemeData.estimateBrightnessForColor(backgroundColor);
    final foregroundColor =
        bgBrightness == Brightness.dark ? Colors.white : AppTheme.darkText;

    final borderColor = bgBrightness == Brightness.dark
        ? Colors.white.withOpacity(0.14)
        : AppTheme.darkText.withOpacity(0.10);

    final label = _localizedStatus(context, status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: foregroundColor,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
