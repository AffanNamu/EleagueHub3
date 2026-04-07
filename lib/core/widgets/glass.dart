import 'dart:ui';
import 'package:flutter/foundation.dart';
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

    // On web, we force a slightly more opaque fill since we bypass blur.
    final double effectiveOpacity = kIsWeb ? (opacity + 0.15).clamp(0.0, 1.0) : opacity;
    final effectiveFill = (fill ?? AppTheme.cardColor(brightness))
        .withOpacity(effectiveOpacity);

    final effectiveBorderEnabled = enableBorder ?? border;
    final effectiveBorderColor =
        borderColor ?? AppTheme.cardBorder(brightness);

    // FATAL WEB CRASH FIX: Nested blurred shadows on high-res desktop monitors 
    // cause WebGL max texture size limit crashes. Stripping them on web fixes it.
    final effectiveShadow = kIsWeb 
        ? null 
        : (boxShadow ?? AppTheme.softCardShadow(brightness));

    final content = Container(
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
    );

    if (kIsWeb || blur <= 0) {
      return ClipRRect(
        borderRadius: br,
        child: content,
      );
    }

    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: content,
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

    // Same web crash fix: disable shadows on web desktop, increase opacity slightly
    final baseColor = fill ?? AppTheme.cardColor(brightness);
    final effectiveFill = kIsWeb 
        ? baseColor.withOpacity((baseColor.opacity + 0.15).clamp(0.0, 1.0)) 
        : baseColor;

    final effectiveShadow = kIsWeb 
        ? null 
        : (boxShadow ?? AppTheme.softCardShadow(brightness));

    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: br,
        color: effectiveFill,
        border: Border.all(
          color: borderColor ?? AppTheme.cardBorder(brightness),
        ),
        boxShadow: effectiveShadow,
      ),
      child: child,
    );

    if (kIsWeb || blur <= 0) {
      return ClipRRect(
        borderRadius: br,
        child: content,
      );
    }

    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: content,
      ),
    );
  }
}
