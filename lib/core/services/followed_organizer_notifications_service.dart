import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';
import '../../features/master_leagues/data/organizer_feed_firebase.dart';
import '../../features/master_leagues/domain/organizer_feed_event.dart';

class FollowedOrganizerNotificationsService {
  FollowedOrganizerNotificationsService._();

  static final FollowedOrganizerNotificationsService instance =
      FollowedOrganizerNotificationsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final OrganizerFeedFirebase _feed = OrganizerFeedFirebase();

  StreamSubscription<List<OrganizerFeedEvent>>? _feedSub;
  StreamSubscription<User?>? _authSub;

  bool _started = false;
  String _activeUid = '';
  final Set<String> _seenFeedIds = <String>{};

  String _lastSeenDocPath(String uid) => 'users/$uid/private/app_state';
  String _lastSeenField() => 'lastSeenOrganizerFeedAtMs';

  Future<void> init() async {
    if (_started) return;
    _started = true;

    await NotificationService().init();

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      await _feedSub?.cancel();
      _feedSub = null;
      _seenFeedIds.clear();
      _activeUid = user?.uid.trim() ?? '';

      if (_activeUid.isEmpty) return;

      int lastSeenAtMs = 0;
      try {
        final snap = await _firestore
            .doc(_lastSeenDocPath(_activeUid))
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 12));
        final data = snap.data() as Map<String, dynamic>? ?? <String, dynamic>{};
        final v = data[_lastSeenField()];
        if (v is int) lastSeenAtMs = v;
        if (v is num) lastSeenAtMs = v.toInt();
      } catch (_) {
        lastSeenAtMs = 0;
      }

      _feedSub = _feed.watchFollowedOrganizerFeedPreview(_activeUid).listen(
        (items) async {
          for (final item in items) {
            if (item.id.trim().isEmpty) continue;
            if (_seenFeedIds.contains(item.id.trim())) continue;

            _seenFeedIds.add(item.id.trim());

            if (item.createdAtMs <= lastSeenAtMs) continue;

            final route = item.leagueId.trim().isNotEmpty
                ? '/leagues/${item.leagueId.trim()}'
                : '/master-leagues/${item.masterLeagueId.trim()}';

            final title = _notificationTitle(item);
            final body = item.message.trim().isEmpty ? item.title.trim() : item.message.trim();

            try {
              await NotificationService().showOrganizerFeedNotification(
                notificationId: _stableIdFromString(item.id.trim()),
                title: title,
                message: body,
                payloadRoute: route,
              );
            } catch (_) {}
          }

          if (items.isNotEmpty) {
            final newest = items
                .map((e) => e.createdAtMs)
                .fold<int>(0, (prev, e) => e > prev ? e : prev);

            if (newest > 0) {
              try {
                await _firestore.doc(_lastSeenDocPath(_activeUid)).set(
                  <String, dynamic>{
                    _lastSeenField(): newest,
                    'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
                  },
                  SetOptions(merge: true),
                );
              } catch (_) {}
            }
          }
        },
      );
    });
  }

  Future<void> dispose() async {
    await _feedSub?.cancel();
    await _authSub?.cancel();
    _feedSub = null;
    _authSub = null;
    _seenFeedIds.clear();
    _activeUid = '';
    _started = false;
  }

  String _notificationTitle(OrganizerFeedEvent item) {
    switch (item.type.trim().toLowerCase()) {
      case 'announcement':
        return 'Organizer announcement';
      case 'competition_created':
        return 'New competition created';
      case 'verification_approved':
        return 'Organizer verified';
      case 'verification_renewed':
        return 'Verification renewed';
      default:
        return item.title.trim().isEmpty ? 'Organizer update' : item.title.trim();
    }
  }

  int _stableIdFromString(String s) {
    final h = s.hashCode;
    return h < 0 ? -h : h;
  }
}
