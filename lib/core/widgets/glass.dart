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

    return ClipRRect(
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
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}
