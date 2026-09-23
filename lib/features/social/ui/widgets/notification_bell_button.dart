// lib/features/social/ui/widgets/notification_bell_button.dart
//
// Self-contained AppBar action: a bell icon with an unread-count badge,
// combining PlatformAnnouncementsRepository.watchUnreadCount() (admin
// broadcast) and PersonalNotificationsRepository.watchUnreadCount()
// (new follower, organizer posts, ...) into one total — the two stay
// separate streams/collections, only their counts are summed here.
// Badge text follows the standard convention: 1-9 shown exactly, 10+
// shown as "9+". Tapping navigates to NotificationsListScreen, which
// renders both sources merged into one list.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/locale/app_localizations.dart';
import '../../data/personal_notifications_repository.dart';
import '../../data/platform_announcements_repository.dart';
import '../screens/notifications_list_screen.dart';

class NotificationBellButton extends StatefulWidget {
  const NotificationBellButton({super.key});

  @override
  State<NotificationBellButton> createState() =>
      _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton> {
  final _announcementsRepo = PlatformAnnouncementsRepository();
  final _personalRepo = PersonalNotificationsRepository();

  int _announcementsCount = 0;
  int _personalCount = 0;

  StreamSubscription<int>? _announcementsSub;
  StreamSubscription<int>? _personalSub;

  @override
  void initState() {
    super.initState();
    _announcementsSub = _announcementsRepo.watchUnreadCount().listen((count) {
      if (!mounted) return;
      setState(() => _announcementsCount = count);
    });
    _personalSub = _personalRepo.watchUnreadCount().listen((count) {
      if (!mounted) return;
      setState(() => _personalCount = count);
    });
  }

  @override
  void dispose() {
    _announcementsSub?.cancel();
    _personalSub?.cancel();
    super.dispose();
  }

  String _badgeLabel(int count) {
    if (count <= 0) return '';
    if (count > 9) return '9+';
    return '$count';
  }

  @override
  Widget build(BuildContext context) {
    final count = _announcementsCount + _personalCount;
    final label = _badgeLabel(count);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          tooltip: context.l10n.tr('notification_bell_tooltip'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NotificationsListScreen(),
              ),
            );
          },
        ),
        if (label.isNotEmpty)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 1,
              ),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: const BoxDecoration(
                color: Color(0xFFEF4444),
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
