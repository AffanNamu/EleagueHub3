import 'dart:ui';

import 'package:flutter/material.dart';

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding = const EdgeInsets.all(16),
    this.blur = 12.0,
    this.opacity = 0.08,
    this.border = true,

    // Backward/forward compatible params (so other widgets can pass them)
    // without forcing you to edit those widgets.
    this.fill,
    this.enableBorder,
    this.borderColor,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double blur;

  /// Used when [fill] is null (keeps existing behavior everywhere else).
  final double opacity;

  /// Existing API: whether to draw border.
  final bool border;

  /// New API: explicit fill color (used by offline_banner.dart).
  /// If provided, it overrides [opacity]/default fill.
  final Color? fill;

  /// New API: alias for border (used by offline_banner.dart).
  /// If provided, it overrides [border].
  final bool? enableBorder;

  /// Optional override for border color (safe default kept).
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(borderRadius);

    final effectiveFill = fill ?? Colors.white.withOpacity(opacity);
    final effectiveBorderEnabled = enableBorder ?? border;
    final effectiveBorderColor = borderColor ?? Colors.white.withOpacity(0.12);

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
    this.blur = 10.0,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(18);
    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: br,
            color: Colors.white.withOpacity(0.05),
            border: Border.all(
              color: Colors.white.withOpacity(0.10),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
