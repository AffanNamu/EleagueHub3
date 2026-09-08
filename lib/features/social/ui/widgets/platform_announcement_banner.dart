// lib/features/social/ui/widgets/platform_announcement_banner.dart
//
// NEW FILE — self-contained, drop-in widget. Streams the latest active
// platform_announcements doc and renders a dismissible-for-this-session
// banner. Renders SizedBox.shrink() when there's no active announcement,
// so it's always safe to place unconditionally in a list of children.

import 'package:flutter/material.dart';

import '../../data/platform_announcements_repository.dart';

class PlatformAnnouncementBanner extends StatefulWidget {
  const PlatformAnnouncementBanner({super.key});

  @override
  State<PlatformAnnouncementBanner> createState() =>
      _PlatformAnnouncementBannerState();
}

class _PlatformAnnouncementBannerState
    extends State<PlatformAnnouncementBanner> {
  final _repo = PlatformAnnouncementsRepository();

  /// Dismissed only for the current app session — reopening the app
  /// shows it again if it's still active. No per-user persisted
  /// dismissal state exists yet (would need a new subcollection write
  /// per user, intentionally not added for this v1).
  String? _dismissedId;

  Color _severityColor(String severity) {
    switch (severity) {
      case 'critical':
        return const Color(0xFFEF4444);
      case 'warning':
        return const Color(0xFFF59E0B);
      case 'info':
      default:
        return const Color(0xFF4C6FFF);
    }
  }

  IconData _severityIcon(String severity) {
    switch (severity) {
      case 'critical':
        return Icons.error_outline_rounded;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'info':
      default:
        return Icons.campaign_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlatformAnnouncement?>(
      stream: _repo.watchLatestActive(),
      builder: (context, snapshot) {
        final announcement = snapshot.data;
        if (announcement == null || announcement.id == _dismissedId) {
          return const SizedBox.shrink();
        }

        final color = _severityColor(announcement.severity);

        return Container(
          margin: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_severityIcon(announcement.severity), color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      announcement.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      announcement.message,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color
                            ?.withOpacity(0.75),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _dismissedId = announcement.id),
              ),
            ],
          ),
        );
      },
    );
  }
}
