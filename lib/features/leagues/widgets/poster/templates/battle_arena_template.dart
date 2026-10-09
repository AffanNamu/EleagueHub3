// lib/features/leagues/widgets/poster/templates/battle_arena_template.dart
//
// 🔥 Battle Arena -- the flagship template. Each side of the matchup gets
// its own lit half of the background (home=lime, away=blue) with a hard
// diagonal seam, large team visuals, and a dramatic VS at the center.

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../models/match_poster_data.dart';
import '../match_poster_kit.dart';
import '../match_poster_template.dart';

class BattleArenaTemplate extends MatchPosterTemplate {
  const BattleArenaTemplate();

  static const Color _homeColor = AppTheme.limeAccent;
  static const Color _awayColor = Color(0xFF3B82F6);

  @override
  String get id => 'battle_arena';
  @override
  String get name => 'Battle Arena';
  @override
  String get emoji => '🔥';

  @override
  Widget build(BuildContext context, MatchPosterData data, MatchPosterFormat format) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 1080.0;
        final m = PosterLayoutMetrics.forFormat(format, width);
        final s = m.scale;

        final hasDetails = (data.dateTimeLabel ?? '').trim().isNotEmpty ||
            (data.venueLabel ?? '').trim().isNotEmpty;

        return Stack(
          fit: StackFit.expand,
          children: [
            const PosterDiagonalSplit(
              leftColor: _homeColor,
              rightColor: _awayColor,
              baseColor: Color(0xFF07090A),
            ),
            Positioned(
              top: -120 * s,
              left: -80 * s,
              child: PosterGlow(size: 420 * s, color: _homeColor.withOpacity(0.22)),
            ),
            Positioned(
              bottom: -140 * s,
              right: -80 * s,
              child: PosterGlow(size: 460 * s, color: _awayColor.withOpacity(0.22)),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(40 * s, 52 * s, 40 * s, 36 * s),
              child: Column(
                children: [
                  _TopBrand(scale: s),
                  SizedBox(height: 10 * s),
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
                    PosterPill(text: data.roundLabel!.trim().toUpperCase(), scale: s, color: Colors.white),
                  ],
                  Expanded(
                    child: Center(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: _TeamColumn(team: data.home, metrics: m, accentColor: _homeColor),
                          ),
                          PosterVsBadge(size: m.vsSize * 1.15, color: Colors.white, textColor: const Color(0xFF07090A)),
                          Expanded(
                            child: _TeamColumn(team: data.away, metrics: m, accentColor: _awayColor),
                          ),
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
                            background: Colors.black.withOpacity(0.32),
                          ),
                          PosterDetailChip(
                            icon: Icons.place_rounded,
                            text: (data.venueLabel ?? '').trim(),
                            scale: s,
                            background: Colors.black.withOpacity(0.32),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    'CREATE. COMPETE. CONNECT.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12 * s,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2 * s,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TopBrand extends StatelessWidget {
  const _TopBrand({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Text(
      'eSPORTLYIC',
      style: TextStyle(
        color: Colors.white,
        fontSize: 16 * scale,
        fontWeight: FontWeight.w900,
        letterSpacing: 3 * scale,
      ),
    );
  }
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({required this.team, required this.metrics, required this.accentColor});
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
          borderWidth: 4 * metrics.scale,
        ),
        SizedBox(height: 16 * metrics.scale),
        Text(
          team.name.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 24 * metrics.scale,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4 * metrics.scale,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}
