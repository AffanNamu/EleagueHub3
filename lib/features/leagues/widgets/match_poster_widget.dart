// lib/features/leagues/widgets/match_poster_widget.dart
//
// The visual poster itself. Pure presentation — takes a MatchPosterData and
// renders it. Deliberately theme-independent (always the same dark broadcast
// look) because this gets exported as an image shared outside the app; it
// should not change appearance based on the viewer's current device theme.
//
// Architected as "Classic" — the first of what Section 9 of the brief calls
// for as an extensible MatchPosterTemplate family. Additional templates
// (e.g. MatchPosterWidgetMinimal, MatchPosterWidgetChampionship) can be
// added later as siblings implementing the same (data) -> Widget contract
// without touching this file.

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/match_poster_data.dart';

class MatchPosterWidget extends StatelessWidget {
  const MatchPosterWidget({super.key, required this.data});

  final MatchPosterData data;

  static const double _designWidth = 1080;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _designWidth;
        final scale = width / _designWidth;

        return Container(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0A0F0B),
                Color(0xFF121A14),
                Color(0xFF0A0F0B),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -90 * scale,
                right: -90 * scale,
                child: _Glow(
                  scale: scale,
                  color: AppTheme.limeAccent.withOpacity(0.16),
                ),
              ),
              Positioned(
                bottom: -120 * scale,
                left: -100 * scale,
                child: _Glow(
                  scale: scale,
                  color: AppTheme.limeAccent.withOpacity(0.08),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  56 * scale,
                  64 * scale,
                  56 * scale,
                  48 * scale,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildHeader(scale),
                    const Spacer(),
                    _buildMatchup(scale),
                    const Spacer(),
                    _buildFooter(scale),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(double scale) {
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
            fontSize: 34 * scale,
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
          _Pill(
            text: data.roundLabel!.trim().toUpperCase(),
            scale: scale,
          ),
        ],
      ],
    );
  }

  Widget _buildMatchup(double scale) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _TeamColumn(team: data.home, scale: scale)),
        _VsBadge(scale: scale),
        Expanded(child: _TeamColumn(team: data.away, scale: scale)),
      ],
    );
  }

  Widget _buildFooter(double scale) {
    final hasDetails = (data.dateTimeLabel ?? '').trim().isNotEmpty ||
        (data.venueLabel ?? '').trim().isNotEmpty ||
        (data.footballCategory ?? '').trim().isNotEmpty;

    return Column(
      children: [
        if (hasDetails) ...[
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10 * scale,
            runSpacing: 8 * scale,
            children: [
              if ((data.dateTimeLabel ?? '').trim().isNotEmpty)
                _DetailChip(
                  icon: Icons.event_rounded,
                  text: data.dateTimeLabel!.trim(),
                  scale: scale,
                ),
              if ((data.venueLabel ?? '').trim().isNotEmpty)
                _DetailChip(
                  icon: Icons.place_rounded,
                  text: data.venueLabel!.trim(),
                  scale: scale,
                ),
              if ((data.footballCategory ?? '').trim().isNotEmpty)
                _DetailChip(
                  icon: Icons.sports_esports_rounded,
                  text: data.footballCategory!.trim(),
                  scale: scale,
                ),
            ],
          ),
          SizedBox(height: 24 * scale),
        ],
        Container(
          height: 1,
          width: 120 * scale,
          color: Colors.white.withOpacity(0.14),
        ),
        SizedBox(height: 14 * scale),
        Text(
          'eSPORTLYIC',
          style: TextStyle(
            color: AppTheme.limeAccent,
            fontSize: 18 * scale,
            fontWeight: FontWeight.w900,
            letterSpacing: 3 * scale,
          ),
        ),
      ],
    );
  }
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({required this.team, required this.scale});

  final MatchPosterTeamData team;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final avatarSize = 168 * scale;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: avatarSize,
          height: avatarSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTheme.limeAccent.withOpacity(0.55),
              width: 3 * scale,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.limeAccent.withOpacity(0.18),
                blurRadius: 24 * scale,
                spreadRadius: 2 * scale,
              ),
            ],
          ),
          padding: EdgeInsets.all(4 * scale),
          child: ClipOval(
            child: Container(
              color: Colors.white.withOpacity(0.06),
              child: team.hasImage
                  ? Image.network(
                      team.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _TeamFallbackIcon(scale: scale),
                      loadingBuilder: (context, child, event) {
                        if (event == null) return child;
                        return _TeamFallbackIcon(scale: scale);
                      },
                    )
                  : _TeamFallbackIcon(scale: scale),
            ),
          ),
        ),
        SizedBox(height: 18 * scale),
        Text(
          team.name.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 24 * scale,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4 * scale,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _TeamFallbackIcon extends StatelessWidget {
  const _TeamFallbackIcon({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.shield_rounded,
        color: Colors.white.withOpacity(0.35),
        size: 64 * scale,
      ),
    );
  }
}

class _VsBadge extends StatelessWidget {
  const _VsBadge({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 10 * scale),
      child: Container(
        width: 64 * scale,
        height: 64 * scale,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.limeAccent,
          boxShadow: [
            BoxShadow(
              color: AppTheme.limeAccent.withOpacity(0.35),
              blurRadius: 20 * scale,
              spreadRadius: 1 * scale,
            ),
          ],
        ),
        child: Text(
          'VS',
          style: TextStyle(
            color: AppTheme.darkText,
            fontSize: 20 * scale,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5 * scale,
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.scale});
  final String text;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 16 * scale,
        vertical: 8 * scale,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: AppTheme.limeAccent.withOpacity(0.12),
        border: Border.all(color: AppTheme.limeAccent.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppTheme.limeAccent,
          fontSize: 14 * scale,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2 * scale,
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.icon,
    required this.text,
    required this.scale,
  });

  final IconData icon;
  final String text;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 12 * scale,
        vertical: 7 * scale,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15 * scale, color: Colors.white.withOpacity(0.75)),
          SizedBox(width: 6 * scale),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 13 * scale,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.scale, required this.color});
  final double scale;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final size = 260 * scale;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0.0)],
        ),
      ),
    );
  }
}
