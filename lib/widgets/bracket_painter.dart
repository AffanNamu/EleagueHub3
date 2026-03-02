import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Draws bracket connectors between two adjacent rounds.
///
/// This painter assumes a classic single-elimination bracket on ONE side:
/// - `fromMatchCount` feeds into `toMatchCount` (normally half).
/// - Matches are positioned using standard bracket spacing math based on
///   `maxMatches` (the earliest round match count on that side).
///
/// It intentionally does NOT try to detect actual widget positions.
/// Instead, it draws a premium bracket using consistent slot spacing.
/// For perfect alignment, the UI must position match cards using the same math.
class BracketPainter extends CustomPainter {
  /// Earliest round match count on the side (must be power of two: 1,2,4,8,...)
  final int maxMatches;

  /// Number of matches in the "from" column that this connector represents.
  final int fromMatchCount;

  /// Connector direction.
  /// - true: from left column to right column
  /// - false: from right column to left column
  final bool isLeftToRight;

  /// Match card height used by the bracket layout.
  final double cardHeight;

  /// Base vertical gap between match cards in the earliest round.
  /// The "slot unit" becomes: cardHeight + baseGap.
  final double baseGap;

  /// Optional override for the connector line color.
  /// If not provided, a brightness-aware default is used.
  final Color? lineColor;

  /// Stroke width for bracket lines.
  final double strokeWidth;

  const BracketPainter({
    required this.maxMatches,
    required this.fromMatchCount,
    this.isLeftToRight = true,
    required this.cardHeight,
    required this.baseGap,
    this.lineColor,
    this.strokeWidth = 1.8,
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

    // ratio = 2^r
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

    // Standard bracket center position formula:
    // centerY = cardHeight/2 + ((2^r - 1)/2)*unit + index*(2^r)*unit
    final offset = ((pow2 - 1) / 2.0) * unit;
    final step = pow2 * unit;

    return (cardHeight / 2.0) + offset + index * step;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (fromMatchCount <= 0) return;
    if (maxMatches <= 0) return;

    // If input isn't a clean bracket, bail silently (avoid ugly lines).
    if (!_isPowerOfTwo(maxMatches) || maxMatches % fromMatchCount != 0) return;

    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;

    // Light theme: premium bluish connector tint (matches the new white theme direction).
    // Dark theme: keep subtle white.
    final resolvedColor = lineColor ??
        (brightness == Brightness.dark
            ? Colors.white24
            : const Color(0x337AB6FF)); // soft blue-tint for light backgrounds

    final xStart = isLeftToRight ? 0.0 : size.width;
    final xEnd = isLeftToRight ? size.width : 0.0;
    final xMid = size.width * 0.52;

    // Premium subtle gradient.
    final shaderRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final shader = LinearGradient(
      begin: isLeftToRight ? Alignment.centerLeft : Alignment.centerRight,
      end: isLeftToRight ? Alignment.centerRight : Alignment.centerLeft,
      colors: [
        resolvedColor.withOpacity(0.90),
        resolvedColor.withOpacity(0.30),
      ],
    ).createShader(shaderRect);

    final paint = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    final toMatchCount = math.max(1, fromMatchCount ~/ 2);

    // Single feeder (e.g., SF on one side feeding the Final):
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

      final toIndex = (i ~/ 2);
      if (toIndex >= toMatchCount) continue;

      final yTo = _centerY(maxMatches: maxMatches, count: toMatchCount, index: toIndex);

      // From match 1 -> join
      canvas.drawLine(Offset(xStart, y0), Offset(xMid, y0), paint);
      // From match 2 -> join
      canvas.drawLine(Offset(xStart, y1), Offset(xMid, y1), paint);
      // Vertical join
      canvas.drawLine(Offset(xMid, y0), Offset(xMid, y1), paint);
      // Join -> next round slot
      canvas.drawLine(Offset(xMid, yTo), Offset(xEnd, yTo), paint);

      // Small node dot for premium feel
      final dotPaint = Paint()..color = resolvedColor.withOpacity(0.55);
      canvas.drawCircle(Offset(xMid, yTo), 2.2, dotPaint);
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
        oldDelegate.strokeWidth != strokeWidth;
  }
}
