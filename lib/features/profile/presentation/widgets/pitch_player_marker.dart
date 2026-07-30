// lib/features/profile/presentation/widgets/pitch_player_marker.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/squad.dart';

/// FIFA-card-inspired token: a tall rounded card with the player's photo
/// filling most of it, a shirt-number badge in the corner, and a name
/// banner along the bottom. Renders inside a square bounding box of
/// [size] x [size] (so pitch positioning math elsewhere is unaffected)
/// with the actual card centered and slightly taller than it is wide.
class PitchPlayerMarker extends StatelessWidget {
  const PitchPlayerMarker({
    super.key,
    required this.slotLabel,
    required this.player,
    required this.isCaptain,
    required this.isViceCaptain,
    required this.size,
    this.onTap,
    this.dense = false,
  });

  /// The formation slot this marker occupies (e.g. "ST"). Shown as a
  /// faint label when the slot is empty.
  final String slotLabel;

  /// Null when no player has been assigned to this slot yet.
  final SquadPlayerSlot? player;

  final bool isCaptain;
  final bool isViceCaptain;

  /// Bounding box side length in logical pixels. The visual card is
  /// rendered narrower and taller than this, centered within it.
  final double size;

  final VoidCallback? onTap;

  /// Compact mode used on narrow mobile pitches — shrinks the name text.
  final bool dense;

  bool get _hasPhoto => (player?.photoUrl ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final hasPlayer = player != null && player!.name.trim().isNotEmpty;

    final cardWidth = size * 0.9;
    final cardHeight = size * 1.28;

    final borderColor = hasPlayer
        ? AppTheme.limeAccentDark
        : AppTheme.cardBorder(brightness).withOpacity(0.6);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: cardWidth,
                height: cardHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(cardWidth * 0.18),
                  border: Border.all(color: borderColor, width: 2),
                  gradient: hasPlayer
                      ? const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF1F2937), Color(0xFF0B1220)],
                        )
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppTheme.cardColor(brightness).withOpacity(0.55),
                            AppTheme.cardColor(brightness).withOpacity(0.35),
                          ],
                        ),
                  boxShadow: hasPlayer
                      ? [
                          BoxShadow(
                            color: AppTheme.limeAccentDark.withOpacity(0.28),
                            blurRadius: 10,
                            spreadRadius: 0.5,
                          ),
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Photo (or fallback icon) fills the upper ~70% of the card.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: cardHeight * 0.72,
                      child: _hasPhoto
                          ? Image.network(
                              player!.photoUrl,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.low,
                              loadingBuilder: (context, child, event) {
                                if (event == null) return child;
                                return _PhotoFallback(hasPlayer: hasPlayer, spinner: true);
                              },
                              errorBuilder: (_, __, ___) =>
                                  _PhotoFallback(hasPlayer: hasPlayer),
                            )
                          : _PhotoFallback(hasPlayer: hasPlayer),
                    ),

                    // Bottom name/position banner.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: cardHeight * 0.28,
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: hasPlayer
                              ? Colors.black.withOpacity(0.55)
                              : Colors.transparent,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              hasPlayer ? player!.name.toUpperCase() : slotLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: hasPlayer
                                    ? Colors.white
                                    : AppTheme.secondaryText(brightness).withOpacity(0.8),
                                fontWeight: FontWeight.w900,
                                fontSize: dense ? size * 0.11 : size * 0.13,
                                letterSpacing: 0.2,
                              ),
                            ),
                            if (hasPlayer && !dense)
                              Text(
                                slotLabel,
                                style: TextStyle(
                                  color: AppTheme.limeAccent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: size * 0.10,
                                  letterSpacing: 0.6,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Shirt-number badge, top-left.
                    if (hasPlayer && player!.shirtNumber > 0)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.limeAccent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${player!.shirtNumber}',
                            style: TextStyle(
                              color: AppTheme.darkText,
                              fontWeight: FontWeight.w900,
                              fontSize: size * 0.11,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (isCaptain)
                Positioned(
                  top: -6,
                  right: (size - cardWidth) / 2 - 6,
                  child: _badge('C', const Color(0xFFFFB300)),
                ),
              if (isViceCaptain && !isCaptain)
                Positioned(
                  top: -6,
                  right: (size - cardWidth) / 2 - 6,
                  child: _badge('V', const Color(0xFF94A3B8)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String letter, Color color) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 1.4),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback({required this.hasPlayer, this.spinner = false});

  final bool hasPlayer;
  final bool spinner;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111827),
      alignment: Alignment.center,
      child: spinner
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 1.8, color: Color(0xFF9CA3AF)),
            )
          : Icon(
              Icons.person,
              color: hasPlayer ? Colors.white70 : Colors.white24,
              size: 26,
            ),
    );
  }
}
