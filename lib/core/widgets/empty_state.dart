import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.iconSize = 40,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final double iconSize;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;

    return Glass(
      borderRadius: 24,
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: AppTheme.iconCircleBackground(brightness),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: iconSize,
              color: AppTheme.limeAccentDark,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: t.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryText(brightness),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: t.bodyMedium?.copyWith(
              color: AppTheme.secondaryText(brightness),
            ),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            action!,
          ],
        ],
      ),
    );
  }
}
