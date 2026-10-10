// lib/features/social/ui/screens/notifications_list_screen.dart
//
// Unified Instagram/Twitter-style inbox: merges 3 sources into one
// chronologically-sorted list:
//   - platform_announcements (admin broadcast, legacy -- nothing writes
//     here anymore, kept read-only so pre-cutover history isn't lost)
//   - home_content announcements (admin broadcast, current -- see
//     HomeContentRepository.watchRecentAnnouncements for why this is a
//     separate, non-schedule-filtered query from the Home tab's own
//     home_content read)
//   - personal notifications (new follower, organizer announcements from
//     workspaces you follow, ...; PersonalNotificationsRepository)
// All 3 stay separate collections/streams at the data layer (very
// different security shapes) and are only merged here, at render time.
//
// Marks everything seen (bumps all 3 per-user read cursors) as soon as the
// screen opens — matches the standard "opening the inbox clears the
// badge" convention.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/locale/app_localizations.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/utils/cloudinary_utils.dart';
import '../../data/home_content_repository.dart';
import '../../data/personal_notifications_repository.dart';
import '../../data/platform_announcements_repository.dart';

class NotificationsListScreen extends StatefulWidget {
  const NotificationsListScreen({super.key});

  @override
  State<NotificationsListScreen> createState() =>
      _NotificationsListScreenState();
}

/// Renders either kind of inbox entry through one shared shape, so the
/// list below doesn't need to branch per-type beyond picking the leading
/// icon/avatar and building createdAtMs for the merge-sort.
class _InboxEntry {
  const _InboxEntry({
    required this.createdAtMs,
    required this.leading,
    required this.title,
    required this.message,
    required this.route,
  });

  final int createdAtMs;
  final Widget leading;
  final String title;
  final String message;
  final String route;
}

class _NotificationsListScreenState extends State<NotificationsListScreen> {
  final _announcementsRepo = PlatformAnnouncementsRepository();
  final _homeContentRepo = HomeContentRepository();
  final _personalRepo = PersonalNotificationsRepository();

  List<PlatformAnnouncement> _announcements = const <PlatformAnnouncement>[];
  List<HomeContentItem> _homeAnnouncements = const <HomeContentItem>[];
  List<PersonalNotification> _personal = const <PersonalNotification>[];
  bool _loadedOnce = false;

  StreamSubscription<List<PlatformAnnouncement>>? _announcementsSub;
  StreamSubscription<List<HomeContentItem>>? _homeAnnouncementsSub;
  StreamSubscription<List<PersonalNotification>>? _personalSub;

  @override
  void initState() {
    super.initState();
    _announcementsRepo.markAllSeen();
    _homeContentRepo.markAnnouncementSeen(DateTime.now().millisecondsSinceEpoch);
    _personalRepo.markAllSeen();

    _announcementsSub = _announcementsRepo.watchRecent().listen((items) {
      if (!mounted) return;
      setState(() {
        _announcements = items;
        _loadedOnce = true;
      });
    });

    _homeAnnouncementsSub =
        _homeContentRepo.watchRecentAnnouncements().listen((items) {
      if (!mounted) return;
      setState(() {
        _homeAnnouncements = items;
        _loadedOnce = true;
      });
    });

    _personalSub = _personalRepo.watchRecent().listen((items) {
      if (!mounted) return;
      setState(() {
        _personal = items;
        _loadedOnce = true;
      });
    });
  }

  @override
  void dispose() {
    _announcementsSub?.cancel();
    _homeAnnouncementsSub?.cancel();
    _personalSub?.cancel();
    super.dispose();
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

  IconData _personalTypeIcon(String type) {
    switch (type) {
      case 'new_follower':
        return Icons.person_add_alt_1_rounded;
      case 'organizer_announcement':
        return Icons.campaign_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Widget _personalLeading(PersonalNotification item) {
    final avatar = item.actorAvatarUrl.trim();
    if (avatar.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: NetworkImage(CloudinaryUtils.thumb(avatar, size: 72)),
        onBackgroundImageError: (_, __) {},
        child: avatar.isEmpty
            ? Icon(_personalTypeIcon(item.type), size: 18)
            : null,
      );
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0xFF4C6FFF).withOpacity(0.15),
      child: Icon(
        _personalTypeIcon(item.type),
        size: 18,
        color: const Color(0xFF4C6FFF),
      ),
    );
  }

  List<_InboxEntry> _mergedEntries() {
    final entries = <_InboxEntry>[
      ..._announcements.map(
        (a) => _InboxEntry(
          createdAtMs: a.createdAtMs,
          leading: Icon(_severityIcon(a.severity),
              color: _severityColor(a.severity), size: 20),
          title: a.title,
          message: a.message,
          route: '',
        ),
      ),
      ..._homeAnnouncements.map(
        (a) => _InboxEntry(
          createdAtMs: a.createdAtMs,
          leading: Icon(_severityIcon(a.severity),
              color: _severityColor(a.severity), size: 20),
          title: a.title,
          message: a.subtitle,
          route: a.ctaRoute,
        ),
      ),
      ..._personal.map(
        (n) => _InboxEntry(
          createdAtMs: n.createdAtMs,
          leading: _personalLeading(n),
          title: n.title,
          message: n.message,
          route: n.route,
        ),
      ),
    ];

    entries.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return entries;
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
    final items = _mergedEntries();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('notifications_list_appbar_title'))),
      body: Builder(
        builder: (context) {
          if (!_loadedOnce && items.isEmpty) {
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
              const color = Color(0xFF4C6FFF);

              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: item.route.trim().isEmpty
                    ? null
                    : () => appRouter.go(item.route.trim()),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      item.leading,
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
                ),
              );
            },
          );
        },
      ),
    );
  }
}
