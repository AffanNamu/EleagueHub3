import 'package:flutter/material.dart';

import 'glass.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    // Many screens use dark-tinted Glass even in light mode.
    // If this header is rendered inside Glass, default "onSurface" (navy in light)
    // can become unreadable. Detect and adapt.
    final bool insideGlass = context.findAncestorWidgetOfExactType<Glass>() != null;

    final Color titleColor = insideGlass ? Colors.white : colorScheme.onSurface;

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: titleColor,
                letterSpacing: 0.3,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}
