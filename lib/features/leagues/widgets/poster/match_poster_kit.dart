// lib/features/leagues/widgets/poster/match_poster_kit.dart
//
// Shared visual primitives used by every MatchPosterTemplate. Nothing here
// is template-specific styling (that lives in each template file) -- this
// is just the reusable building blocks: a team identity panel with a real
// image-or-initials fallback (never an empty circle), a VS badge, info
// chips, a diagonal split background, and a glow blob. Every template
// composes these with its own colors/sizes rather than re-implementing
// them, per the "share common rendering components" requirement.

import 'package:flutter/material.dart';

import '../../../../core/utils/cloudinary_utils.dart';
import '../../models/match_poster_data.dart';

/// Derives 1-2 letter initials from a team name for the image fallback --
/// never a generic placeholder icon. "Thunder Hawks" -> "TH", "Liverpool"
/// -> "LI", empty/whitespace-only name -> "?".
String posterInitialsFor(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';

  final words = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.length >= 2) {
    return (words[0][0] + words[1][0]).toUpperCase();
  }
  final word = words.first;
  return word.length >= 2 ? word.substring(0, 2).toUpperCase() : word.toUpperCase();
}

/// A large team identity treatment: real logo/photo when the team has one
/// (Cloudinary-resized to the actual display size, never the raw upload),
/// otherwise a generated initials badge in the given accent color. Shape
/// and size are template-controlled so the same primitive can be a hero
/// circle, a rounded panel, or a tall portrait slot.
class PosterTeamVisual extends StatelessWidget {
  const PosterTeamVisual({
    super.key,
    required this.team,
    required this.size,
    required this.accentColor,
    this.shape = BoxShape.circle,
    this.borderRadius = 0,
    this.borderWidth = 3,
    this.glow = true,
  });

  final MatchPosterTeamData team;
  final double size;
  final Color accentColor;
  final BoxShape shape;
  final double borderRadius;
  final double borderWidth;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final radius = shape == BoxShape.circle
        ? BorderRadius.circular(size)
        : BorderRadius.circular(borderRadius);

    final content = team.hasImage
        ? Image.network(
            CloudinaryUtils.fill(
              team.imageUrl,
              width: size.round(),
              height: size.round(),
            ),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _InitialsFallback(
              name: team.name,
              accentColor: accentColor,
            ),
          )
        : _InitialsFallback(name: team.name, accentColor: accentColor);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: shape == BoxShape.rectangle ? radius : null,
        border: Border.all(color: accentColor.withOpacity(0.65), width: borderWidth),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: accentColor.withOpacity(0.35),
                  blurRadius: size * 0.22,
                  spreadRadius: size * 0.02,
                ),
              ]
            : null,
      ),
      padding: EdgeInsets.all(borderWidth + 1),
      child: ClipRRect(
        borderRadius: shape == BoxShape.circle ? BorderRadius.circular(size) : radius,
        child: Container(
          color: Colors.white.withOpacity(0.05),
          child: content,
        ),
      ),
    );
  }
}

class _InitialsFallback extends StatelessWidget {
  const _InitialsFallback({required this.name, required this.accentColor});
  final String name;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [accentColor.withOpacity(0.35), accentColor.withOpacity(0.12)],
        ),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        child: Text(
          posterInitialsFor(name),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 40,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// A strong, high-contrast VS badge -- never the small afterthought of the
/// old design. [size] drives both the badge diameter and the text scale.
class PosterVsBadge extends StatelessWidget {
  const PosterVsBadge({
    super.key,
    required this.size,
    required this.color,
    this.textColor = Colors.black,
  });

  final double size;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.55), blurRadius: size * 0.4, spreadRadius: size * 0.03),
        ],
      ),
      child: Text(
        'VS',
        style: TextStyle(
          color: textColor,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Small rounded info chip (date/time/venue/platform). Omits itself
/// entirely when [text] is blank -- callers should already guard this, but
/// it's safe either way.
class PosterDetailChip extends StatelessWidget {
  const PosterDetailChip({
    super.key,
    required this.icon,
    required this.text,
    required this.scale,
    this.foreground = Colors.white,
    this.background,
    this.borderColor,
  });

  final IconData icon;
  final String text;
  final double scale;
  final Color foreground;
  final Color? background;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 7 * scale),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: background ?? Colors.white.withOpacity(0.08),
        border: Border.all(color: borderColor ?? Colors.white.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15 * scale, color: foreground.withOpacity(0.85)),
          SizedBox(width: 6 * scale),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: foreground.withOpacity(0.92), fontSize: 13 * scale, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Pill badge used for round/competition-stage labels.
class PosterPill extends StatelessWidget {
  const PosterPill({
    super.key,
    required this.text,
    required this.scale,
    required this.color,
  });

  final String text;
  final double scale;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 8 * scale),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(0.14),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 14 * scale, fontWeight: FontWeight.w900, letterSpacing: 1.2 * scale),
      ),
    );
  }
}

/// Soft radial glow blob, used as a background accent. Purely decorative.
class PosterGlow extends StatelessWidget {
  const PosterGlow({super.key, required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withOpacity(0.0)]),
      ),
    );
  }
}

/// A crisp (non-blended) diagonal two-color split background, used by the
/// templates that give each side of the matchup its own color identity
/// (e.g. Battle Arena: home=lime, away=blue). A plain LinearGradient blends
/// at the seam; this clips a hard edge instead, which reads as far more
/// "competitive event" than a soft gradient.
class PosterDiagonalSplit extends StatelessWidget {
  const PosterDiagonalSplit({
    super.key,
    required this.leftColor,
    required this.rightColor,
    required this.baseColor,
    this.skew = 0.12,
  });

  final Color leftColor;
  final Color rightColor;
  final Color baseColor;

  /// Fraction of width the diagonal leans, 0 = vertical split down the
  /// middle, positive leans the top edge rightward.
  final double skew;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: baseColor),
        ClipPath(
          clipper: _DiagonalClipper(skew: skew, rightSide: false),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [leftColor.withOpacity(0.22), leftColor.withOpacity(0.02)],
              ),
            ),
          ),
        ),
        ClipPath(
          clipper: _DiagonalClipper(skew: skew, rightSide: true),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [rightColor.withOpacity(0.22), rightColor.withOpacity(0.02)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DiagonalClipper extends CustomClipper<Path> {
  const _DiagonalClipper({required this.skew, required this.rightSide});
  final double skew;
  final bool rightSide;

  @override
  Path getClip(Size size) {
    final midX = size.width / 2;
    final lean = size.width * skew;
    final path = Path();
    if (!rightSide) {
      path.moveTo(0, 0);
      path.lineTo(midX + lean, 0);
      path.lineTo(midX - lean, size.height);
      path.lineTo(0, size.height);
      path.close();
    } else {
      path.moveTo(midX + lean, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(midX - lean, size.height);
      path.close();
    }
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
