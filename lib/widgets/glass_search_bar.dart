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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final brightness = theme.brightness;

    final fill = AppTheme.glassFill(brightness);
    final stroke = AppTheme.glassStroke(brightness);

    final textColor = cs.onSurface;

    final isLight = brightness == Brightness.light;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: stroke),
              boxShadow: isLight
                  ? <BoxShadow>[
                      BoxShadow(
                        color: const Color(0xFFB4D2FF).withOpacity(0.18),
                        blurRadius: 22,
                        offset: const Offset(0, 14),
                      ),
                    ]
                  : null,
            ),
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.tr('glass_search_bar_hint'),
                hintStyle: TextStyle(
                  color: textColor.withOpacity(0.55),
                  fontWeight: FontWeight.w600,
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
