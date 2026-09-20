// lib/features/social/ui/screens/notifications_list_screen.dart
//
// Full list of recent platform announcements. Marks everything seen
// (bumps the per-user read cursor) as soon as the screen opens — matches
// the standard "opening the inbox clears the badge" convention.

import 'package:flutter/material.dart';

import '../../../../core/locale/app_localizations.dart';
import '../../data/platform_announcements_repository.dart';

class NotificationsListScreen extends StatefulWidget {
  const NotificationsListScreen({super.key});

  @override
  State<NotificationsListScreen> createState() =>
      _NotificationsListScreenState();
}

class _NotificationsListScreenState extends State<NotificationsListScreen> {
  final _repo = PlatformAnnouncementsRepository();

  @override
  void initState() {
    super.initState();
    _repo.markAllSeen();
  }

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

  String _relativeTime(AppLocalizations l10n, int ms) {
    if (ms <= 0) return '';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return l10n.tr('notifications_list_time_just_now');
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}${l10n.tr('notifications_list_time_minutes_ago_suffix')}';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}${l10n.tr('notifications_list_time_hours_ago_suffix')}';
    }
    return '${diff.inDays}${l10n.tr('notifications_list_time_days_ago_suffix')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('notifications_list_appbar_title'))),
      body: StreamBuilder<List<PlatformAnnouncement>>(
        stream: _repo.watchRecent(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <PlatformAnnouncement>[];

          if (snapshot.connectionState == ConnectionState.waiting &&
              items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.tr('notifications_list_empty'),
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              final color = _severityColor(item.severity);

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_severityIcon(item.severity), color: color, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.message,
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _relativeTime(l10n, item.createdAtMs),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
