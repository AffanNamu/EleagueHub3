import 'dart:math';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Animated bubble background with floating, drifting bubbles.
class AnimatedBubbleBackground extends StatefulWidget {
  const AnimatedBubbleBackground({super.key});

  @override
  State<AnimatedBubbleBackground> createState() => _AnimatedBubbleBackgroundState();
}

class _AnimatedBubbleBackgroundState extends State<AnimatedBubbleBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Bubble> _bubbles;
  final Random _rng = Random(); // dynamic random seed

  @override
  void initState() {
    super.initState();

    // Animation controller for bubble movement
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();

    // Generate bubbles
    _bubbles = List.generate(18, (_) => _Bubble.random(_rng));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final colors = AppTheme.bubblePalette(brightness);

    return IgnorePointer(
      ignoring: true,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _BubblePainter(
                t: _controller.value,
                bubbles: _bubbles,
                colors: colors,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Single bubble data model
class _Bubble {
  _Bubble({
    required this.seed,
    required this.baseX,
    required this.baseY,
    required this.radius,
    required this.drift,
    required this.speed,
    required this.phase,
    required this.colorIndex,
  });

  final double seed;
  final double baseX; // 0..1 horizontal position
  final double baseY; // 0..1 vertical position
  final double radius; // relative size factor
  final double drift; // horizontal/vertical drift factor
  final double speed; // movement speed multiplier
  final double phase; // initial phase offset
  final int colorIndex; // index in color palette

  factory _Bubble.random(Random rng) {
    return _Bubble(
      seed: rng.nextDouble() * 9999,
      baseX: rng.nextDouble(),
      baseY: rng.nextDouble(),
      radius: 0.03 + rng.nextDouble() * 0.08,
      drift: 0.10 + rng.nextDouble() * 0.35,
      speed: 0.25 + rng.nextDouble() * 1.2,
      phase: rng.nextDouble() * pi * 2,
      // Palette has 4 colors in both themes; modulo is applied when painting anyway.
      colorIndex: rng.nextInt(4),
    );
  }
}

/// Custom painter for bubbles
class _BubblePainter extends CustomPainter {
  _BubblePainter({
    required this.t,
    required this.bubbles,
    required this.colors,
  });

  final double t; // animation progress 0..1
  final List<_Bubble> bubbles;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final dt = t * 2 * pi;

    for (final b in bubbles) {
      // Bobble cycle: slow Lissajous-ish movement around base point
      final wobbleX = sin(dt * (0.6 * b.speed) + b.phase) * b.drift;
      final wobbleY = cos(dt * (0.45 * b.speed) + b.phase) * b.drift;

      final x = (b.baseX + wobbleX * 0.12) * size.width;
      final y = (b.baseY + wobbleY * 0.10) * size.height;

      final r = b.radius * min(size.width, size.height) * (0.85 + 0.25 * sin(dt * 0.9 + b.phase));

      final paint = Paint()
        ..color = colors[b.colorIndex % colors.length]
        ..isAntiAlias = true;

      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BubblePainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.colors != colors;
  }
}
