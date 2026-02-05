import 'dart:ui';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Reusable glassmorphism container
/// Handles blur, fill, stroke, and theming automatically
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16.0),
    this.borderRadius = 20.0,
    this.blurSigma = 18.0,
    this.fill,
    this.stroke,
    this.enableBorder = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final double borderRadius;
  final double blurSigma;
  final Color? fill;
  final Color? stroke;
  final bool enableBorder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final fillColor = fill ?? AppTheme.glassFill(brightness);
    final strokeColor = stroke ?? AppTheme.glassStroke(brightness);

    // If the effective glass fill is dark (common in our design), default text/icons inside
    // should be white so users can see what they type without having to set styles everywhere.
    // If the glass fill is light (e.g., login card overrides fill to near-white),
    // we DO NOT force white defaults.
    final bool isDarkGlass = fillColor.computeLuminance() < 0.45;

    // When in LIGHT theme but inside dark-tinted glass, override input decorations so
    // TextFields have readable label/hint/borders (white-ish), while the app-wide theme
    // keeps dark inputs for normal light surfaces.
    ThemeData effectiveTheme = theme;
    if (isDarkGlass && brightness == Brightness.light) {
      effectiveTheme = theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: Colors.white.withOpacity(0.06),
          labelStyle: const TextStyle(color: Colors.white70),
          hintStyle: const TextStyle(color: Colors.white54),
          prefixIconColor: Colors.white70,
          suffixIconColor: Colors.white70,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: theme.colorScheme.primary.withOpacity(0.90), width: 1.4),
          ),
        ),
        textSelectionTheme: theme.textSelectionTheme.copyWith(
          cursorColor: theme.colorScheme.primary,
          selectionColor: theme.colorScheme.primary.withOpacity(0.25),
          selectionHandleColor: theme.colorScheme.primary,
        ),
      );
    }

    Widget content = Padding(
      padding: padding,
      child: child,
    );

    if (isDarkGlass) {
      content = DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: IconTheme.merge(
          data: IconThemeData(color: Colors.white.withOpacity(0.85)),
          child: content,
        ),
      );
    }

    return Theme(
      data: effectiveTheme,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(borderRadius),
              border: enableBorder
                  ? Border.all(
                      color: strokeColor,
                      width: 1,
                    )
                  : null,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
