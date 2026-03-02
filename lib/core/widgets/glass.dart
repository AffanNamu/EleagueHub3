import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding = const EdgeInsets.all(16),
    this.blur = 18.0,
    this.opacity = 0.08,
    this.border = true,
    this.fill,
    this.enableBorder,
    this.borderColor,
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

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final br = BorderRadius.circular(borderRadius);

    final effectiveFill =
        fill ?? AppTheme.glassFill(brightness);

    final effectiveBorderEnabled =
        enableBorder ?? border;

    final effectiveBorderColor =
        borderColor ?? AppTheme.glassStroke(brightness);

    final lightGlow = brightness == Brightness.light
        ? [
            BoxShadow(
              color: const Color(0x667AB6FF),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ]
        : null;

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
            boxShadow: lightGlow,
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
    this.blur = 16.0,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final br = borderRadius ?? BorderRadius.circular(22);

    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: br,
            color: AppTheme.glassFill(brightness),
            border: Border.all(
              color: AppTheme.glassStroke(brightness),
            ),
            boxShadow: brightness == Brightness.light
                ? [
                    const BoxShadow(
                      color: Color(0x557AB6FF),
                      blurRadius: 28,
                      offset: Offset(0, 16),
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
