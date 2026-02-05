import 'package:flutter/material.dart';

/// Draws the connector lines between tournament rounds.
class BracketPainter extends CustomPainter {
  final int matchCount;
  final bool isLeftToRight;

  /// Optional override for the connector line color.
  /// If not provided, a brightness-aware default is used.
  final Color? lineColor;

  BracketPainter({
    required this.matchCount,
    this.isLeftToRight = true,
    this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (matchCount <= 0) return;

    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;

    final resolvedColor = lineColor ??
        (brightness == Brightness.dark
            ? Colors.white24
            : const Color(0x260A1D37)); // deep-navy tint for light backgrounds

    final paint = Paint()
      ..color = resolvedColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final double xStart = isLeftToRight ? 0 : size.width;
    final double xMid = size.width / 2;

    for (int i = 0; i < matchCount; i++) {
      // Logic for vertical spacing and horizontal "forks"
      final double y = (size.height / matchCount) * (i + 0.5);

      canvas.drawLine(Offset(xStart, y), Offset(xMid, y), paint);

      // Connect top and bottom matches to a single point in the next round
      if (i % 2 == 0) {
        final double nextY = (size.height / matchCount) * (i + 1);
        canvas.drawLine(
          Offset(xMid, y),
          Offset(xMid, nextY + (size.height / matchCount) * 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant BracketPainter oldDelegate) {
    return oldDelegate.matchCount != matchCount ||
        oldDelegate.isLeftToRight != isLeftToRight ||
        oldDelegate.lineColor != lineColor;
  }
}
