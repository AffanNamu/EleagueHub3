// lib/features/leagues/widgets/poster/templates/championship_template.dart
//
// 🏆 Championship -- premium tournament style for finals/semis/important
// matches. Gold + eSportlyic green on a cinematic dark background, trophy
// motif up top, stadium-light glow.

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../models/match_poster_data.dart';
import '../match_poster_kit.dart';
import '../match_poster_template.dart';

class ChampionshipTemplate extends MatchPosterTemplate {
  const ChampionshipTemplate();

  static const Color _gold = Color(0xFFE8B84B);

  @override
  String get id => 'championship';
  @override
  String get name => 'Championship';
  @override
  String get emoji => '🏆';

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
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0C0A05), Color(0xFF1A1509), Color(0xFF0C0A05)],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Stadium-light beams from the top.
              Positioned(
                top: -60 * s,
                left: width * 0.5 - 300 * s,
                child: PosterGlow(size: 600 * s, color: _gold.withOpacity(0.16)),
              ),
              Positioned(
                top: -20 * s,
                left: -60 * s,
                child: PosterGlow(size: 260 * s, color: AppTheme.limeAccent.withOpacity(0.08)),
              ),
              Positioned(
                top: -20 * s,
                right: -60 * s,
                child: PosterGlow(size: 260 * s, color: AppTheme.limeAccent.withOpacity(0.08)),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(44 * s, 48 * s, 44 * s, 36 * s),
                child: Column(
                  children: [
                    Icon(Icons.emoji_events_rounded, color: _gold, size: 46 * s),
                    SizedBox(height: 10 * s),
                    Text(
                      data.competitionName.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32 * s,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2 * s,
                      ),
                    ),
                    if ((data.season ?? '').trim().isNotEmpty) ...[
                      SizedBox(height: 6 * s),
                      Text(
                        data.season!.trim(),
                        style: TextStyle(
                          color: _gold.withOpacity(0.75),
                          fontSize: 15 * s,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4 * s,
                        ),
                      ),
                    ],
                    if ((data.roundLabel ?? '').trim().isNotEmpty) ...[
                      SizedBox(height: 14 * s),
                      PosterPill(text: data.roundLabel!.trim().toUpperCase(), scale: s, color: _gold),
                    ],
                    Expanded(
                      child: Center(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: _TeamBlock(team: data.home, metrics: m)),
                            PosterVsBadge(size: m.vsSize, color: _gold, textColor: const Color(0xFF0C0A05)),
                            Expanded(child: _TeamBlock(team: data.away, metrics: m)),
                          ],
                        ),
                      ),
                    ),
                    if (hasDetails)
                      Padding(
                        padding: EdgeInsets.only(bottom: 16 * s),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 10 * s,
                          runSpacing: 8 * s,
                          children: [
                            PosterDetailChip(
                              icon: Icons.event_rounded,
                              text: (data.dateTimeLabel ?? '').trim(),
                              scale: s,
                              borderColor: _gold.withOpacity(0.35),
                            ),
                            PosterDetailChip(
                              icon: Icons.place_rounded,
                              text: (data.venueLabel ?? '').trim(),
                              scale: s,
                              borderColor: _gold.withOpacity(0.35),
                            ),
                          ],
                        ),
                      ),
                    Container(height: 1, width: 110 * s, color: _gold.withOpacity(0.3)),
                    SizedBox(height: 12 * s),
                    Text(
                      'eSPORTLYIC',
                      style: TextStyle(
                        color: _gold,
                        fontSize: 17 * s,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3 * s,
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

class _TeamBlock extends StatelessWidget {
  const _TeamBlock({required this.team, required this.metrics});
  final MatchPosterTeamData team;
  final PosterLayoutMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PosterTeamVisual(
          team: team,
          size: metrics.teamVisualSize,
          accentColor: ChampionshipTemplate._gold,
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
