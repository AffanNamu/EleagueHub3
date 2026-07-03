// lib/features/verification/presentation/widgets/verification_badge_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/badge_model.dart';
import '../../logic/badge_providers.dart';

/// Displays the appropriate verification badge icon(s) for a user.
///
/// Usage — inline next to a username:
/// Row(children: [
///   Text(user.name),
///   VerificationBadgeWidget(userId: user.id),
/// ])
///
/// This widget does NOT redesign any existing screen.
/// Drop it in wherever a badge icon is needed.
class VerificationBadgeWidget extends ConsumerWidget {
  final String userId;
  
  /// If true, shows all badges the user owns.
  /// If false, shows only the highest-priority badge.
  final bool showAll;
  
  /// Icon size — defaults to 16 (inline with text).
  final double size;
  
  const VerificationBadgeWidget({
    super.key,
    required this.userId,
    this.showAll = false,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgeAsync = ref.watch(badgeStreamProvider(userId));
    
    return badgeAsync.when(
      data: (badges) => _BadgeRow(
        badges: badges,
        showAll: showAll,
        size: size,
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _BadgeRow extends StatelessWidget {
  final VerificationBadges badges;
  final bool showAll;
  final double size;
  
  const _BadgeRow({
    required this.badges,
    required this.showAll,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> icons = [];
    
    // Staff badge — highest priority visual indicator.
    if (badges.isStaffActive) {
      icons.add(_BadgeIcon(
        icon: Icons.shield_rounded,
        color: Colors.deepPurple,
        label: 'Staff / Ambassador',
        size: size,
      ));
      if (!showAll) return _wrap(icons);
    }
    
    // Gold organizer badge.
    if (badges.isOrganizerActive) {
      icons.add(_BadgeIcon(
        icon: Icons.verified_rounded,
        color: const Color(0xFFFFB300), // amber/gold
        label: 'Official Organizer',
        size: size,
      ));
      if (!showAll) return _wrap(icons);
    }
    
    // Green verified badge.
    if (badges.isGreenActive) {
      icons.add(_BadgeIcon(
        icon: Icons.verified_rounded,
        color: const Color(0xFF00C853), // app green accent
        label: 'Verified User',
        size: size,
      ));
    }
    
    if (icons.isEmpty) return const SizedBox.shrink();
    return _wrap(icons);
  }

  Widget _wrap(List<Widget> icons) {
    if (icons.isEmpty) return const SizedBox.shrink();
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: icons
          .map((icon) => Padding(
                padding: const EdgeInsets.only(left: 3),
                child: icon,
              ))
          .toList(),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final double size;
  
  const _BadgeIcon({
    required this.icon,
    required this.color,
    required this.label,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Icon(
        icon,
        color: color,
        size: size,
      ),
    );
  }
}
