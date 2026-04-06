import 'package:flutter/material.dart';

import '../core/locale/app_localizations.dart';
import '../core/theme/app_theme.dart';

class GlassSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  const GlassSearchBar({
    super.key,
    this.controller,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final fill = AppTheme.searchBackground(brightness);
    final stroke = AppTheme.searchOutline(brightness);
    final textColor = AppTheme.primaryText(brightness);
    final hintColor = AppTheme.secondaryText(brightness);

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: stroke),
          boxShadow: AppTheme.softCardShadow(brightness),
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            isDense: true,
            hintText: l10n.tr('glass_search_bar_hint'),
            hintStyle: TextStyle(
              color: hintColor,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Icon(
              Icons.search,
              color: hintColor,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }
}
