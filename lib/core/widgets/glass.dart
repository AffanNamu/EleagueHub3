import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding = const EdgeInsets.all(16),
    this.blur = 14.0,
    this.opacity = 1,
    this.border = true,
    this.fill,
    this.enableBorder,
    this.borderColor,
    this.boxShadow,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final double opacity;
  final bool border;
  final Color? fill;
  final bool? enableBorder;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final br = BorderRadius.circular(borderRadius);

    final effectiveFill = (fill ?? AppTheme.cardColor(brightness))
        .withOpacity(opacity.clamp(0, 1));

    final effectiveBorderEnabled = enableBorder ?? border;
    final effectiveBorderColor =
        borderColor ?? AppTheme.cardBorder(brightness);

    final effectiveShadow =
        boxShadow ?? AppTheme.softCardShadow(brightness);

    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: br,
            color: effectiveFill,
            border: effectiveBorderEnabled
                ? Border.all(color: effectiveBorderColor)
                : null,
            boxShadow: effectiveShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.blur = 14.0,
    this.fill,
    this.borderColor,
    this.boxShadow,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final double blur;
  final Color? fill;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final br = borderRadius ?? BorderRadius.circular(24);

    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: br,
            color: fill ?? AppTheme.cardColor(brightness),
            border: Border.all(
              color: borderColor ?? AppTheme.cardBorder(brightness),
            ),
            boxShadow: boxShadow ?? AppTheme.softCardShadow(brightness),
          ),
          child: child,
        ),
      ),
    );
  }
}
