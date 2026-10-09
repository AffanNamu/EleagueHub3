// lib/features/leagues/widgets/poster/templates/neon_clash_template.dart
//
// ⚡ Neon Clash -- futuristic competitive-gaming look. Near-black
// background, neon lime + electric blue geometric accent lines, large
// team visuals in rounded-square glowing panels rather than circles.

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../models/match_poster_data.dart';
import '../match_poster_kit.dart';
import '../match_poster_template.dart';

class NeonClashTemplate extends MatchPosterTemplate {
  const NeonClashTemplate();

  static const Color _lime = AppTheme.limeAccent;
  static const Color _blue = Color(0xFF22D3EE);

  @override
  String get id => 'neon_clash';
  @override
  String get name => 'Neon Clash';
  @override
  String get emoji => '⚡';

  @override
  Widget build(BuildContext context, MatchPosterData data, MatchPosterFormat format) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 1080.0;
        final m = PosterLayoutMetrics.forFormat(format, width);
        final s = m.scale;

        final hasDetails = (data.dateTimeLabel ?? '').trim().isNotEmpty ||
            (data.venueLabel ?? '').trim().isNotEmpty;

        return Container(
          color: const Color(0xFF060709),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _LightTrailsPainter(scale: s)),
              Positioned(
                top: -100 * s,
                right: -100 * s,
                child: PosterGlow(size: 420 * s, color: _blue.withOpacity(0.2)),
              ),
              Positioned(
                bottom: -110 * s,
                left: -90 * s,
                child: PosterGlow(size: 440 * s, color: _lime.withOpacity(0.2)),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(40 * s, 52 * s, 40 * s, 36 * s),
                child: Column(
                  children: [
                    Text(
                      'eSPORTLYIC',
                      style: TextStyle(
                        color: _lime,
                        fontSize: 15 * s,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4 * s,
                      ),
                    ),
                    SizedBox(height: 12 * s),
                    Text(
                      data.competitionName.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30 * s,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0 * s,
                      ),
                    ),
                    if ((data.roundLabel ?? '').trim().isNotEmpty) ...[
                      SizedBox(height: 12 * s),
                      PosterPill(text: data.roundLabel!.trim().toUpperCase(), scale: s, color: _blue),
                    ],
                    Expanded(
                      child: Center(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: _TeamPanel(team: data.home, metrics: m, accentColor: _lime)),
                            PosterVsBadge(size: m.vsSize, color: Colors.white, textColor: const Color(0xFF060709)),
                            Expanded(child: _TeamPanel(team: data.away, metrics: m, accentColor: _blue)),
                          ],
                        ),
                      ),
                    ),
                    if (hasDetails)
                      Padding(
                        padding: EdgeInsets.only(bottom: 14 * s),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 10 * s,
                          runSpacing: 8 * s,
                          children: [
                            PosterDetailChip(
                              icon: Icons.event_rounded,
                              text: (data.dateTimeLabel ?? '').trim(),
                              scale: s,
                              borderColor: _blue.withOpacity(0.4),
                            ),
                            PosterDetailChip(
                              icon: Icons.place_rounded,
                              text: (data.venueLabel ?? '').trim(),
                              scale: s,
                              borderColor: _lime.withOpacity(0.4),
                            ),
                          ],
                        ),
                      ),
                    Container(height: 1, width: 100 * s, color: Colors.white.withOpacity(0.14)),
                    SizedBox(height: 12 * s),
                    Text(
                      'CREATE. COMPETE. CONNECT.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 11 * s,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2 * s,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TeamPanel extends StatelessWidget {
  const _TeamPanel({required this.team, required this.metrics, required this.accentColor});
  final MatchPosterTeamData team;
  final PosterLayoutMetrics metrics;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PosterTeamVisual(
          team: team,
          size: metrics.teamVisualSize,
          accentColor: accentColor,
          shape: BoxShape.rectangle,
          borderRadius: 28 * metrics.scale,
          borderWidth: 3 * metrics.scale,
        ),
        SizedBox(height: 16 * metrics.scale),
        Text(
          team.name.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 23 * metrics.scale,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4 * metrics.scale,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

/// A handful of thin diagonal light-trail lines across the background --
/// decorative only, deliberately sparse (not "excessive glow").
class _LightTrailsPainter extends CustomPainter {
  const _LightTrailsPainter({required this.scale});
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2 * scale
      ..style = PaintingStyle.stroke;

    final lines = <({double dx, Color color, double opacity})>[
      (dx: size.width * 0.18, color: AppTheme.limeAccent, opacity: 0.18),
      (dx: size.width * 0.30, color: const Color(0xFF22D3EE), opacity: 0.12),
      (dx: size.width * 0.78, color: const Color(0xFF22D3EE), opacity: 0.16),
      (dx: size.width * 0.88, color: AppTheme.limeAccent, opacity: 0.12),
    ];

    for (final line in lines) {
      paint.color = line.color.withOpacity(line.opacity);
      canvas.drawLine(
        Offset(line.dx, 0),
        Offset(line.dx - size.width * 0.12, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LightTrailsPainter oldDelegate) => false;
}
