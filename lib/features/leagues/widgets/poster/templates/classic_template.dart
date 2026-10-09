// lib/features/leagues/widgets/poster/templates/classic_template.dart
//
// 💚 eSportlyic Classic -- the recognizable default. Same navy/lime
// eSportlyic identity as the original single-template poster, but with the
// hero matchup now dominating the composition instead of floating in two
// Spacer()-sized empty regions.

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../models/match_poster_data.dart';
import '../match_poster_kit.dart';
import '../match_poster_template.dart';

class ClassicTemplate extends MatchPosterTemplate {
  const ClassicTemplate();

  @override
  String get id => 'classic';
  @override
  String get name => 'eSportlyic Classic';
  @override
  String get emoji => '💚';

  @override
  Widget build(BuildContext context, MatchPosterData data, MatchPosterFormat format) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 1080.0;
        final m = PosterLayoutMetrics.forFormat(format, width);
        final s = m.scale;

        final hasDetails = (data.dateTimeLabel ?? '').trim().isNotEmpty ||
            (data.venueLabel ?? '').trim().isNotEmpty ||
            (data.footballCategory ?? '').trim().isNotEmpty;

        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0A0F0B), Color(0xFF141F17), Color(0xFF0A0F0B)],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: -(m.isTall ? 140 : 100) * s,
                left: width / 2 - 260 * s,
                child: PosterGlow(size: 520 * s, color: AppTheme.limeAccent.withOpacity(0.14)),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(48 * s, 56 * s, 48 * s, 40 * s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _Header(data: data, scale: s),
                    SizedBox(height: (m.isTall ? 56 : 28) * s),
                    Expanded(
                      child: Center(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: _TeamBlock(
                                team: data.home,
                                metrics: m,
                                accentColor: AppTheme.limeAccent,
                              ),
                            ),
                            PosterVsBadge(size: m.vsSize, color: AppTheme.limeAccent),
                            Expanded(
                              child: _TeamBlock(
                                team: data.away,
                                metrics: m,
                                accentColor: AppTheme.limeAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: (m.isTall ? 56 : 28) * s),
                    if (hasDetails) ...[
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10 * s,
                        runSpacing: 8 * s,
                        children: [
                          PosterDetailChip(
                            icon: Icons.event_rounded,
                            text: (data.dateTimeLabel ?? '').trim(),
                            scale: s,
                          ),
                          PosterDetailChip(
                            icon: Icons.place_rounded,
                            text: (data.venueLabel ?? '').trim(),
                            scale: s,
                          ),
                          PosterDetailChip(
                            icon: Icons.sports_esports_rounded,
                            text: (data.footballCategory ?? '').trim(),
                            scale: s,
                          ),
                        ],
                      ),
                      SizedBox(height: 22 * s),
                    ],
                    Container(height: 1, width: 120 * s, color: Colors.white.withOpacity(0.14)),
                    SizedBox(height: 14 * s),
                    Text(
                      'eSPORTLYIC',
                      style: TextStyle(
                        color: AppTheme.limeAccent,
                        fontSize: 18 * s,
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

class _Header extends StatelessWidget {
  const _Header({required this.data, required this.scale});
  final MatchPosterData data;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (data.hasCompetitionLogo) ...[
          ClipOval(
            child: SizedBox(
              width: 72 * scale,
              height: 72 * scale,
              child: Image.network(
                data.competitionLogoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
          SizedBox(height: 14 * scale),
        ],
        Text(
          data.competitionName.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 36 * scale,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1 * scale,
            height: 1.15,
          ),
        ),
        if ((data.season ?? '').trim().isNotEmpty) ...[
          SizedBox(height: 6 * scale),
          Text(
            data.season!.trim(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 16 * scale,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4 * scale,
            ),
          ),
        ],
        if ((data.roundLabel ?? '').trim().isNotEmpty) ...[
          SizedBox(height: 16 * scale),
          PosterPill(text: data.roundLabel!.trim().toUpperCase(), scale: scale, color: AppTheme.limeAccent),
        ],
      ],
    );
  }
}

class _TeamBlock extends StatelessWidget {
  const _TeamBlock({required this.team, required this.metrics, required this.accentColor});
  final MatchPosterTeamData team;
  final PosterLayoutMetrics metrics;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PosterTeamVisual(team: team, size: metrics.teamVisualSize, accentColor: accentColor),
        SizedBox(height: 18 * metrics.scale),
        Text(
          team.name.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 25 * metrics.scale,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4 * metrics.scale,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}
