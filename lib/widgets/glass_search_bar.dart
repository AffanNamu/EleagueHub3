import 'dart:ui';

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
    final brightness = Theme.of(context).brightness;

    final fill = AppTheme.glassFill(brightness);
    final stroke = AppTheme.glassStroke(brightness);

    // This search bar is typically used on top of the app background (GlassScaffold),
    // so keep it readable in light mode too (our light-mode glass is dark-tinted).
    const textColor = Colors.white;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: stroke),
            ),
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(color: textColor),
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.tr('glass_search_bar_hint'),
                hintStyle: TextStyle(
                  color: textColor.withOpacity(0.55),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: textColor.withOpacity(0.72),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
