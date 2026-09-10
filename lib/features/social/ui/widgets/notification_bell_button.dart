// lib/features/social/ui/widgets/notification_bell_button.dart
//
// Self-contained AppBar action: a bell icon with an unread-count badge,
// sourced from PlatformAnnouncementsRepository.watchUnreadCount(). Badge
// text follows the standard convention: 1-9 shown exactly, 10+ shown as
// "9+". Tapping navigates to NotificationsListScreen.

import 'package:flutter/material.dart';

import '../../data/platform_announcements_repository.dart';
import '../screens/notifications_list_screen.dart';

class NotificationBellButton extends StatefulWidget {
  const NotificationBellButton({super.key});

  @override
  State<NotificationBellButton> createState() =>
      _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton> {
  final _repo = PlatformAnnouncementsRepository();

  String _badgeLabel(int count) {
    if (count <= 0) return '';
    if (count > 9) return '9+';
    return '$count';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _repo.watchUnreadCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final label = _badgeLabel(count);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Notifications',
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
      },
    );
  }
}
