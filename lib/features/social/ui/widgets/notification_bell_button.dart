// lib/features/social/ui/widgets/notification_bell_button.dart
//
// Self-contained AppBar action: a bell icon with an unread-count badge,
// combining PlatformAnnouncementsRepository (admin broadcast) and
// PersonalNotificationsRepository (new follower, organizer posts, ...)
// into one total — the two stay separate streams/collections, only
// their counts are summed here.
// Badge text follows the standard convention: 1-9 shown exactly, 10+
// shown as "9+". Tapping navigates to NotificationsListScreen, which
// renders both sources merged into one list.
//
// Opens exactly one users/{uid} Firestore listener (for both cursor
// fields at once) rather than each repository's unread-count stream
// opening its own -- this widget is always mounted in the app shell, so
// a second independent listener here ran for the entire app session.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  int _lastSeenAnnouncementAtMs = 0;
  int _lastSeenPersonalAtMs = 0;
  List<PlatformAnnouncement> _announcementItems = const [];
  List<PersonalNotification> _personalItems = const [];

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  StreamSubscription<List<PlatformAnnouncement>>? _announcementsSub;
  StreamSubscription<List<PersonalNotification>>? _personalSub;

  @override
  void initState() {
    super.initState();

    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isNotEmpty) {
      _userDocSub = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .listen((doc) {
        if (!mounted) return;
        final data = doc.data();
        setState(() {
          _lastSeenAnnouncementAtMs =
              data?['lastSeenAnnouncementAtMs'] is int
                  ? data!['lastSeenAnnouncementAtMs'] as int
                  : 0;
          _lastSeenPersonalAtMs =
              data?['lastSeenPersonalNotificationAtMs'] is int
                  ? data!['lastSeenPersonalNotificationAtMs'] as int
                  : 0;
        });
      });
    }

    _announcementsSub = _announcementsRepo.watchRecent().listen((items) {
      if (!mounted) return;
      setState(() => _announcementItems = items);
    });
    _personalSub = _personalRepo.watchRecent().listen((items) {
      if (!mounted) return;
      setState(() => _personalItems = items);
    });
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
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
    final announcementsCount = PlatformAnnouncementsRepository.countUnread(
      _announcementItems,
      _lastSeenAnnouncementAtMs,
    );
    final personalCount = PersonalNotificationsRepository.countUnread(
      _personalItems,
      _lastSeenPersonalAtMs,
    );
    final count = announcementsCount + personalCount;
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
