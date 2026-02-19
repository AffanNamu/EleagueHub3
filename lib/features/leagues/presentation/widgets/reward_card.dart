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

  static String positionLabel(int position) {
    if (position == 1) return '1st';
    if (position == 2) return '2nd';
    if (position == 3) return '3rd';
    return '${position}th';
  }

  Color _badgeColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (reward.position) {
      case 1:
        return const Color(0xFFFFD54F); // gold
      case 2:
        return const Color(0xFFB0BEC5); // silver-ish
      case 3:
        return const Color(0xFFBCAAA4); // bronze-ish
      default:
        return cs.primary.withValues(alpha: 0.85);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final cardChild = Stack(
      children: <Widget>[
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: reward.imageUrl.trim().isEmpty
                ? Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          cs.primary.withValues(alpha: 0.18),
                          cs.secondary.withValues(alpha: 0.12),
                          Colors.black.withValues(alpha: 0.08),
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
                                  cs.primary.withValues(alpha: 0.18),
                                  cs.secondary.withValues(alpha: 0.12),
                                  Colors.black.withValues(alpha: 0.08),
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
                            colors: <Color>[
                              Colors.black.withValues(alpha: 0.15),
                              Colors.black.withValues(alpha: 0.45),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
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
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
                  gradient: LinearGradient(
                    colors: <Color>[
                      Colors.white.withValues(alpha: 0.10),
                      Colors.white.withValues(alpha: 0.04),
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
            color: _badgeColor(context),
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: _TypeChip(type: reward.rewardType),
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
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          reward.rewardName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: Colors.white,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          reward.description.trim().isEmpty ? '—' : reward.description.trim(),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.85),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: Colors.black.withValues(alpha: 0.85),
                letterSpacing: 0.1,
              ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final label = type.trim().isEmpty ? 'other' : type.trim().toLowerCase();
    final display = label[0].toUpperCase() + label.substring(1);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          display,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.92),
              ),
        ),
      ),
    );
  }
}
