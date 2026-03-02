import 'dart:ui';

import 'package:flutter/material.dart';

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
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;

    final cardChild = Stack(
      children: <Widget>[
        // Background layer
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: reward.imageUrl.trim().isEmpty
                ? Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          cs.primary.withOpacity(isLight ? 0.10 : 0.12),
                          cs.secondary.withOpacity(isLight ? 0.06 : 0.08),
                          cs.onSurface.withOpacity(isLight ? 0.03 : 0.04),
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
                              gradient: LinearGradient(
                                colors: <Color>[
                                  cs.primary.withOpacity(isLight ? 0.10 : 0.12),
                                  cs.secondary
                                      .withOpacity(isLight ? 0.06 : 0.08),
                                  cs.onSurface
                                      .withOpacity(isLight ? 0.03 : 0.04),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          );
                        },
                      ),

                      // Readability overlay
                      // - Light theme: frosted white veil (supports dark text)
                      // - Dark theme: dark veil (supports light/bright accents)
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isLight
                                ? <Color>[
                                    Colors.white.withOpacity(0.18),
                                    Colors.white.withOpacity(0.62),
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

                      // Subtle blue tint glow (light theme only)
                      if (isLight)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: <Color>[
                                cs.primary.withOpacity(0.08),
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

        // Glass overlay
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isLight
                        ? Colors.white.withOpacity(0.55)
                        : cs.onSurface.withOpacity(0.12),
                    width: 1,
                  ),
                  gradient: LinearGradient(
                    colors: isLight
                        ? <Color>[
                            Colors.white.withOpacity(0.22),
                            Colors.white.withOpacity(0.06),
                          ]
                        : <Color>[
                            cs.onSurface.withOpacity(0.08),
                            cs.onSurface.withOpacity(0.03),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
        ),

        // Content
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

        // Position badge
        Positioned(
          left: 12,
          top: 12,
          child: _PositionBadge(
            label: positionLabel(reward.position),
            color: _badgeColor(),
          ),
        ),

        // Type chip
        Positioned(
          right: 12,
          top: 12,
          child: _TypeChip(
            type: reward.rewardType,
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
    final cs = theme.colorScheme;

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
            color: cs.onSurface,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          reward.description.trim().isEmpty ? '—' : reward.description.trim(),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurface.withOpacity(0.72),
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
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.22)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            // Premium light shadow: airy blue glow instead of dark drop shadow.
            color: isLight
                ? cs.primary.withOpacity(0.18)
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
    required this.type,
    required this.color,
  });

  final String type;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = type.trim().isEmpty ? 'other' : type.trim().toLowerCase();
    final display = label[0].toUpperCase() + label.substring(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        display,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: color,
          fontSize: 11,
        ),
      ),
    );
  }
}
