import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass.dart';
import '../../data/models/reward_model.dart';

class RewardCard extends StatelessWidget {
  const RewardCard({
    super.key,
    required this.reward,
    this.onTap,
    this.trailing,
  });

  final RewardModel reward;
  final VoidCallback? onTap;
  final Widget? trailing;

  static const Color _premiumAmber = Color(0xFFF59E0B);
  static const Color _premiumViolet = Color(0xFF8B5CF6);
  static const Color _premiumSky = Color(0xFF38BDF8);
  static const Color _premiumTeal = Color(0xFF2DD4BF);

  static String positionLabel(int position) {
    if (position == 1) return '1st';
    if (position == 2) return '2nd';
    if (position == 3) return '3rd';
    return '${position}th';
  }

  /// Maps a stored [rewardType] value to a user-facing display label.
  ///
  /// Firestore field values (e.g. 'cash', 'physical') are internal identifiers
  /// and must not change. Only the display label presented to users is mapped
  /// here so that no financial terminology appears in the UI.
  static String _typeDisplayLabel(String rewardType) {
    final t = rewardType.trim().toLowerCase();
    switch (t) {
      case 'cash':
        return 'Monetary';
      case 'physical':
        return 'Physical Item';
      case 'digital':
        return 'Digital Item';
      case 'trophy':
        return 'Trophy / Medal';
      case 'other':
        return 'Other';
      default:
        // For any unknown / future type, capitalize first letter as fallback.
        if (t.isEmpty) return 'Other';
        return t[0].toUpperCase() + t.substring(1);
    }
  }

  Color _badgeColor() {
    switch (reward.position) {
      case 1:
        return _premiumAmber;
      case 2:
        return const Color(0xFFB0BEC5);
      case 3:
        return const Color(0xFFBCAAA4);
      default:
        return _premiumSky;
    }
  }

  Color _typeChipColor() {
    final t = reward.rewardType.trim().toLowerCase();
    switch (t) {
      case 'cash':
        return _premiumAmber;
      case 'trophy':
        return _premiumViolet;
      case 'digital':
        return _premiumSky;
      case 'physical':
        return _premiumTeal;
      default:
        return const Color(0xFF94A3B8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isLight = brightness == Brightness.light;

    final cardChild = Stack(
      children: <Widget>[
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: reward.imageUrl.trim().isEmpty
                ? Container(
                    decoration: BoxDecoration(
                      gradient: isLight
                          ? const LinearGradient(
                              colors: <Color>[
                                Color(0xFFFFFFFF),
                                Color(0xFFF9FAFB),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : LinearGradient(
                              colors: <Color>[
                                AppTheme.darkCard,
                                AppTheme.darkCardAlt,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                    ),
                    child: const SizedBox.expand(),
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Image.network(
                        reward.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) {
                          return Container(
                            decoration: BoxDecoration(
                              gradient: isLight
                                  ? const LinearGradient(
                                      colors: <Color>[
                                        Color(0xFFFFFFFF),
                                        Color(0xFFF9FAFB),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : LinearGradient(
                                      colors: <Color>[
                                        AppTheme.darkCard,
                                        AppTheme.darkCardAlt,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                            ),
                          );
                        },
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isLight
                                ? <Color>[
                                    Colors.white.withOpacity(0.25),
                                    Colors.white.withOpacity(0.74),
                                  ]
                                : <Color>[
                                    Colors.black.withOpacity(0.15),
                                    Colors.black.withOpacity(0.50),
                                  ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      if (isLight)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: <Color>[
                                AppTheme.limeAccent.withOpacity(0.06),
                                Colors.transparent,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppTheme.cardBorder(brightness),
                    width: 1,
                  ),
                  gradient: LinearGradient(
                    colors: isLight
                        ? <Color>[
                            Colors.white.withOpacity(0.20),
                            Colors.white.withOpacity(0.04),
                          ]
                        : <Color>[
                            Colors.white.withOpacity(0.08),
                            Colors.white.withOpacity(0.03),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _TitleAndDescription(reward: reward),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: _PositionBadge(
            label: positionLabel(reward.position),
            color: _badgeColor(),
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: _TypeChip(
            displayLabel: _typeDisplayLabel(reward.rewardType),
            color: _typeChipColor(),
          ),
        ),
      ],
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.96, end: 1.0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return AnimatedOpacity(
          opacity: 1,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: GestureDetector(
          onTap: onTap,
          child: GlassCard(
            fill: AppTheme.cardColor(brightness),
            borderColor: AppTheme.cardBorder(brightness),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 140,
                child: cardChild,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleAndDescription extends StatelessWidget {
  const _TitleAndDescription({required this.reward});
  final RewardModel reward;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          reward.rewardName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
            color: AppTheme.primaryText(brightness),
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          reward.description.trim().isEmpty ? '—' : reward.description.trim(),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.secondaryText(brightness),
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _PositionBadge extends StatelessWidget {
  const _PositionBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final isLight = brightness == Brightness.light;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.22)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: isLight
                ? AppTheme.limeAccentDark.withOpacity(0.14)
                : Colors.black.withOpacity(0.15),
            blurRadius: isLight ? 18 : 10,
            offset: isLight ? const Offset(0, 8) : const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: color,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.displayLabel,
    required this.color,
  });

  /// Pre-resolved user-facing display label.
  /// The raw Firestore [rewardType] value is mapped to this label
  /// by [RewardCard._typeDisplayLabel] before being passed here.
  final String displayLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        displayLabel,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: color,
          fontSize: 11,
        ),
      ),
    );
  }
}