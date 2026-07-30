// lib/features/profile/presentation/widgets/pitch_player_marker.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/squad.dart';

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

  /// Diameter of the token in logical pixels.
  final double size;

  final VoidCallback? onTap;

  /// Compact mode used on narrow mobile pitches — hides the name label.
  final bool dense;

  bool get _hasPhoto => (player?.photoUrl ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final hasPlayer = player != null && player!.name.trim().isNotEmpty;

    final fillColor = hasPlayer
        ? AppTheme.limeAccent
        : AppTheme.cardColor(brightness).withOpacity(0.55);
    final borderColor =
        hasPlayer ? AppTheme.limeAccentDark : AppTheme.cardBorder(brightness);
    final textColor =
        hasPlayer ? AppTheme.darkText : AppTheme.secondaryText(brightness);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fillColor,
                  border: Border.all(color: borderColor, width: 2),
                  boxShadow: hasPlayer
                      ? [
                          BoxShadow(
                            color: AppTheme.limeAccentDark.withOpacity(0.35),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: ClipOval(
                  child: _hasPhoto
                      ? Image.network(
                          player!.photoUrl,
                          width: size,
                          height: size,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.low,
                          loadingBuilder: (context, child, event) {
                            if (event == null) return child;
                            return _FallbackLabel(
                              text: hasPlayer
                                  ? (player!.shirtNumber > 0
                                      ? '${player!.shirtNumber}'
                                      : slotLabel)
                                  : slotLabel,
                              color: textColor,
                              fontSize: size * 0.34,
                              spinner: true,
                            );
                          },
                          errorBuilder: (_, __, ___) => _FallbackLabel(
                            text: hasPlayer
                                ? (player!.shirtNumber > 0
                                    ? '${player!.shirtNumber}'
                                    : slotLabel)
                                : slotLabel,
                            color: textColor,
                            fontSize: size * 0.34,
                          ),
                        )
                      : _FallbackLabel(
                          text: hasPlayer
                              ? (player!.shirtNumber > 0
                                  ? '${player!.shirtNumber}'
                                  : slotLabel)
                              : slotLabel,
                          color: textColor,
                          fontSize: size * 0.34,
                        ),
                ),
              ),
              if (isCaptain)
                Positioned(
                  top: -4,
                  right: -4,
                  child: _badge(context, 'C', const Color(0xFFFFB300)),
                ),
              if (isViceCaptain && !isCaptain)
                Positioned(
                  top: -4,
                  right: -4,
                  child: _badge(context, 'V', const Color(0xFF94A3B8)),
                ),
            ],
          ),
          if (!dense) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: size + 24,
              child: Text(
                hasPlayer ? player!.name : slotLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: hasPlayer
                      ? AppTheme.primaryText(brightness)
                      : AppTheme.secondaryText(brightness).withOpacity(0.7),
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _badge(BuildContext context, String letter, Color color) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

/// Centered text shown in place of a photo — used both as the permanent
/// no-photo state and as the transient state while a photo is loading or
/// after it fails to load.
class _FallbackLabel extends StatelessWidget {
  const _FallbackLabel({
    required this.text,
    required this.color,
    required this.fontSize,
    this.spinner = false,
  });

  final String text;
  final Color color;
  final double fontSize;
  final bool spinner;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: spinner
          ? SizedBox(
              width: fontSize * 1.1,
              height: fontSize * 1.1,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
            )
          : Text(
              text,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: fontSize,
              ),
            ),
    );
  }
}
