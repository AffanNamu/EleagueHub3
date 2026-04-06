import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Draws bracket connectors between two adjacent rounds.
class BracketPainter extends CustomPainter {
  final int maxMatches;
  final int fromMatchCount;
  final bool isLeftToRight;
  final double cardHeight;
  final double baseGap;
  final Color? lineColor;
  final double strokeWidth;
  final Brightness? brightness;

  const BracketPainter({
    required this.maxMatches,
    required this.fromMatchCount,
    this.isLeftToRight = true,
    required this.cardHeight,
    required this.baseGap,
    this.lineColor,
    this.strokeWidth = 1.8,
    this.brightness,
  });

  bool _isPowerOfTwo(int v) => v > 0 && (v & (v - 1)) == 0;

  int _roundIndexForCount({
    required int maxMatches,
    required int count,
  }) {
    if (count <= 0 || maxMatches <= 0) return 0;
    if (maxMatches % count != 0) return 0;

    final ratio = maxMatches ~/ count;
    if (!_isPowerOfTwo(ratio)) return 0;

    int r = 0;
    int x = ratio;
    while (x > 1) {
      x ~/= 2;
      r++;
    }
    return r;
  }

  double _centerY({
    required int maxMatches,
    required int count,
    required int index,
  }) {
    final unit = cardHeight + baseGap;
    final r = _roundIndexForCount(maxMatches: maxMatches, count: count);
    final pow2 = 1 << r;

    final offset = ((pow2 - 1) / 2.0) * unit;
    final step = pow2 * unit;

    return (cardHeight / 2.0) + offset + index * step;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (fromMatchCount <= 0) return;
    if (maxMatches <= 0) return;
    if (!_isPowerOfTwo(maxMatches) || maxMatches % fromMatchCount != 0) return;

    final resolvedBrightness =
        brightness ?? WidgetsBinding.instance.platformDispatcher.platformBrightness;

    final resolvedColor = lineColor ??
        (resolvedBrightness == Brightness.dark
            ? const Color(0x55FFFFFF)
            : AppTheme.limeAccentDark.withOpacity(0.28));

    final xStart = isLeftToRight ? 0.0 : size.width;
    final xEnd = isLeftToRight ? size.width : 0.0;
    final xMid = size.width * 0.52;

    final shaderRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final shader = LinearGradient(
      begin: isLeftToRight ? Alignment.centerLeft : Alignment.centerRight,
      end: isLeftToRight ? Alignment.centerRight : Alignment.centerLeft,
      colors: [
        resolvedColor.withOpacity(0.95),
        resolvedColor.withOpacity(0.35),
      ],
    ).createShader(shaderRect);

    final paint = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    final toMatchCount = math.max(1, fromMatchCount ~/ 2);

    if (fromMatchCount == 1) {
      final y = _centerY(maxMatches: maxMatches, count: 1, index: 0);
      canvas.drawLine(Offset(xStart, y), Offset(xEnd, y), paint);
      return;
    }

    for (int i = 0; i < fromMatchCount; i += 2) {
      final i0 = i;
      final i1 = i + 1;

      final y0 = _centerY(maxMatches: maxMatches, count: fromMatchCount, index: i0);
      final y1 = _centerY(maxMatches: maxMatches, count: fromMatchCount, index: i1);

      final toIndex = i ~/ 2;
      if (toIndex >= toMatchCount) continue;

      final yTo = _centerY(maxMatches: maxMatches, count: toMatchCount, index: toIndex);

      canvas.drawLine(Offset(xStart, y0), Offset(xMid, y0), paint);
      canvas.drawLine(Offset(xStart, y1), Offset(xMid, y1), paint);
      canvas.drawLine(Offset(xMid, y0), Offset(xMid, y1), paint);
      canvas.drawLine(Offset(xMid, yTo), Offset(xEnd, yTo), paint);

      final dotPaint = Paint()
        ..color = resolvedColor.withOpacity(0.65)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(xMid, yTo), 2.4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant BracketPainter oldDelegate) {
    return oldDelegate.maxMatches != maxMatches ||
        oldDelegate.fromMatchCount != fromMatchCount ||
        oldDelegate.isLeftToRight != isLeftToRight ||
        oldDelegate.cardHeight != cardHeight ||
        oldDelegate.baseGap != baseGap ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.brightness != brightness;
  }
}
