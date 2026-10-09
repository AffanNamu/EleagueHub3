// lib/features/leagues/widgets/poster/templates/dark_pro_template.dart
//
// 🌑 Dark Pro -- minimal, almost-black, no excessive effects. Large team
// visuals and strong typography do the work; decoration is limited to
// thin neon-lime rule lines. Aimed at serious competitive organizers who
// want the match itself to be the entire story.

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../models/match_poster_data.dart';
import '../match_poster_kit.dart';
import '../match_poster_template.dart';

class DarkProTemplate extends MatchPosterTemplate {
  const DarkProTemplate();

  @override
  String get id => 'dark_pro';
  @override
  String get name => 'Dark Pro';
  @override
  String get emoji => '🌑';

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
          color: const Color(0xFF050505),
          child: Padding(
            padding: EdgeInsets.fromLTRB(44 * s, 52 * s, 44 * s, 36 * s),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 24 * s, height: 2 * s, color: AppTheme.limeAccent),
                    SizedBox(width: 10 * s),
                    Text(
                      'eSPORTLYIC',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 14 * s,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3 * s,
                      ),
                    ),
                    SizedBox(width: 10 * s),
                    Container(width: 24 * s, height: 2 * s, color: AppTheme.limeAccent),
                  ],
                ),
                SizedBox(height: 20 * s),
                Text(
                  data.competitionName.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28 * s,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0 * s,
                  ),
                ),
                if ((data.roundLabel ?? '').trim().isNotEmpty) ...[
                  SizedBox(height: 10 * s),
                  Text(
                    data.roundLabel!.trim().toUpperCase(),
                    style: TextStyle(
                      color: AppTheme.limeAccent,
                      fontSize: 13 * s,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2 * s,
                    ),
                  ),
                ],
                Expanded(
                  child: Center(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: _TeamBlock(team: data.home, metrics: m)),
                        _MinimalVs(scale: s),
                        Expanded(child: _TeamBlock(team: data.away, metrics: m)),
                      ],
                    ),
                  ),
                ),
                if (hasDetails) ...[
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 18 * s,
                    runSpacing: 8 * s,
                    children: [
                      if ((data.dateTimeLabel ?? '').trim().isNotEmpty)
                        _PlainDetail(icon: Icons.event_rounded, text: data.dateTimeLabel!.trim(), scale: s),
                      if ((data.venueLabel ?? '').trim().isNotEmpty)
                        _PlainDetail(icon: Icons.place_rounded, text: data.venueLabel!.trim(), scale: s),
                      if ((data.footballCategory ?? '').trim().isNotEmpty)
                        _PlainDetail(icon: Icons.sports_esports_rounded, text: data.footballCategory!.trim(), scale: s),
                    ],
                  ),
                  SizedBox(height: 18 * s),
                ],
                Container(height: 1, color: Colors.white.withOpacity(0.1)),
                SizedBox(height: 12 * s),
                Text(
                  'CREATE. COMPETE. CONNECT.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 11 * s,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2 * s,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MinimalVs extends StatelessWidget {
  const _MinimalVs({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 14 * scale),
      child: Text(
        'VS',
        style: TextStyle(
          color: AppTheme.limeAccent,
          fontSize: 30 * scale,
          fontWeight: FontWeight.w900,
          letterSpacing: 1 * scale,
        ),
      ),
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
          accentColor: AppTheme.limeAccent,
          shape: BoxShape.rectangle,
          borderRadius: 18 * metrics.scale,
          borderWidth: 1.5 * metrics.scale,
          glow: false,
        ),
        SizedBox(height: 16 * metrics.scale),
        Text(
          team.name.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 22 * metrics.scale,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3 * metrics.scale,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

class _PlainDetail extends StatelessWidget {
  const _PlainDetail({required this.icon, required this.text, required this.scale});
  final IconData icon;
  final String text;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14 * scale, color: Colors.white.withOpacity(0.5)),
        SizedBox(width: 6 * scale),
        Text(
          text,
          style: TextStyle(
            color: Colors.white.withOpacity(0.75),
            fontSize: 13 * scale,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
