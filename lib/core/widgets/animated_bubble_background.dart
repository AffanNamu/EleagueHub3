import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Animated ambient background with soft floating bubbles.
/// On web, animation cost is reduced to avoid heavy full-screen repaints.
class AnimatedBubbleBackground extends StatefulWidget {
  const AnimatedBubbleBackground({super.key});

  @override
  State<AnimatedBubbleBackground> createState() =>
      _AnimatedBubbleBackgroundState();
}

class _AnimatedBubbleBackgroundState extends State<AnimatedBubbleBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Bubble> _bubbles;
  final Random _rng = Random();

  bool get _isWeb => kIsWeb;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: _isWeb ? 28 : 18),
    );

    if (_isWeb) {
      _controller.value = 0.35;
    } else {
      _controller.repeat();
    }

    _bubbles = List.generate(_isWeb ? 8 : 18, (_) => _Bubble.random(_rng));
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
        child: _isWeb
            ? CustomPaint(
                painter: _BubblePainter(
                  t: _controller.value,
                  bubbles: _bubbles,
                  colors: colors,
                  brightness: brightness,
                ),
              )
            : AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _BubblePainter(
                      t: _controller.value,
                      bubbles: _bubbles,
                      colors: colors,
                      brightness: brightness,
                    ),
                  );
                },
              ),
      ),
    );
  }
}

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
  final double baseX;
  final double baseY;
  final double radius;
  final double drift;
  final double speed;
  final double phase;
  final int colorIndex;

  factory _Bubble.random(Random rng) {
    return _Bubble(
      seed: rng.nextDouble() * 9999,
      baseX: rng.nextDouble(),
      baseY: rng.nextDouble(),
      radius: 0.03 + rng.nextDouble() * 0.08,
      drift: 0.10 + rng.nextDouble() * 0.35,
      speed: 0.25 + rng.nextDouble() * 1.2,
      phase: rng.nextDouble() * pi * 2,
      colorIndex: rng.nextInt(4),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({
    required this.t,
    required this.bubbles,
    required this.colors,
    required this.brightness,
  });

  final double t;
  final List<_Bubble> bubbles;
  final List<Color> colors;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final dt = t * 2 * pi;

    for (final b in bubbles) {
      final wobbleX = sin(dt * (0.6 * b.speed) + b.phase) * b.drift;
      final wobbleY = cos(dt * (0.45 * b.speed) + b.phase) * b.drift;

      final x = (b.baseX + wobbleX * 0.12) * size.width;
      final y = (b.baseY + wobbleY * 0.10) * size.height;

      final r = b.radius *
          min(size.width, size.height) *
          (0.85 + 0.25 * sin(dt * 0.9 + b.phase));

      final bubbleColor = colors[b.colorIndex % colors.length];
      final opacity = brightness == Brightness.dark ? 1.0 : 0.58;

      final paint = Paint()
        ..color = bubbleColor.withOpacity(bubbleColor.opacity * opacity)
        ..isAntiAlias = true;

      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BubblePainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.colors != colors ||
        oldDelegate.brightness != brightness;
  }
}
