// lib/features/social/data/personal_notifications_repository.dart
//
// Reads/writes users/{uid}/notifications/{id} — the collection defined in
// firestore.rules, right after /following/{targetId}. An Instagram/
// Twitter-style personal inbox (new follower, organizer announcements from
// workspaces you follow, ...), separate from platform_announcements (admin
// broadcast, read by everyone — a totally different audience/security
// shape, see PlatformAnnouncementsRepository).
//
// Unread tracking mirrors PlatformAnnouncementsRepository exactly: a single
// per-user cursor (users/{uid}.lastSeenPersonalNotificationAtMs), not
// per-item read state. An item counts as unread if createdAtMs is after
// that cursor. markAllSeen() bumps it to "now" when the inbox is opened.
//
// Each doc is created by the ACTOR (the follower, the organizer posting),
// not the inbox owner — firestore.rules gates create on
// actorId == request.auth.uid, same shape as /followers/{followerId}.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

class PersonalNotification {
  const PersonalNotification({
    required this.id,
    required this.type,
    required this.actorId,
    required this.actorName,
    required this.actorAvatarUrl,
    required this.title,
    required this.message,
    required this.imageUrl,
    required this.route,
    required this.createdAtMs,
  });

  final String id;
  final String type;
  final String actorId;
  final String actorName;
  final String actorAvatarUrl;
  final String title;
  final String message;
  final String imageUrl;
  final String route;
  final int createdAtMs;

  factory PersonalNotification.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return PersonalNotification(
      id: doc.id,
      type: (data['type'] as String? ?? '').trim(),
      actorId: (data['actorId'] as String? ?? '').trim(),
      actorName: (data['actorName'] as String? ?? '').trim(),
      actorAvatarUrl: (data['actorAvatarUrl'] as String? ?? '').trim(),
      title: (data['title'] as String? ?? '').trim(),
      message: (data['message'] as String? ?? '').trim(),
      imageUrl: (data['imageUrl'] as String? ?? '').trim(),
      route: (data['route'] as String? ?? '').trim(),
      createdAtMs: data['createdAtMs'] is int ? data['createdAtMs'] as int : 0,
    );
  }
}

class PersonalNotificationsRepository {
  PersonalNotificationsRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  static const Uuid _uuid = Uuid();

  static const int _recentLimit = 50;

  CollectionReference<Map<String, dynamic>> _notificationsCol(String uid) =>
      _firestore.collection('users').doc(uid).collection('notifications');

  /// Streams up to the 50 most recent notifications for the current user,
  /// newest first. Used by the notification list screen and by the bell
  /// badge's unread count.
  Stream<List<PersonalNotification>> watchRecent() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      return Stream<List<PersonalNotification>>.value(
          const <PersonalNotification>[]);
    }

    return _notificationsCol(uid)
        .orderBy('createdAtMs', descending: true)
        .limit(_recentLimit)
        .snapshots()
        .map<List<PersonalNotification>>(
          (snap) => snap.docs.map(PersonalNotification.fromDoc).toList(),
        )
        .handleError((Object _, StackTrace __) => <PersonalNotification>[]);
  }

  /// Pure helper pairing [watchRecent]'s items with the per-user
  /// lastSeenPersonalNotificationAtMs cursor (read from the user doc by
  /// the caller) to get the unread count — same cursor-comparison pattern
  /// as PlatformAnnouncementsRepository.countUnread().
  ///
  /// This used to be its own watchUnreadCount() stream that opened a
  /// second, independent users/{uid} Firestore listener and re-subscribed
  /// to watchRecent() on every unrelated profile write via asyncExpand.
  /// Callers now read the cursor off a listener they already hold and
  /// combine it with [watchRecent] themselves.
  static int countUnread(
    List<PersonalNotification> items,
    int lastSeenAtMs,
  ) {
    return items.where((n) => n.createdAtMs > lastSeenAtMs).length;
  }

  /// Marks all currently-visible notifications as seen by bumping the
  /// per-user cursor to now. Best-effort — a failure here should never
  /// block the notification list from opening.
  Future<void> markAllSeen() async {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    try {
      await _firestore.collection('users').doc(uid).set(
        <String, dynamic>{
          'lastSeenPersonalNotificationAtMs':
              DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> _addNotification({
    required String targetUserId,
    required String type,
    required String actorId,
    required String actorName,
    required String actorAvatarUrl,
    required String title,
    required String message,
    String imageUrl = '',
    String route = '',
  }) async {
    final target = targetUserId.trim();
    if (target.isEmpty) return;

    try {
      await _notificationsCol(target).doc(_uuid.v4()).set(<String, dynamic>{
        'type': type,
        'actorId': actorId.trim(),
        'actorName': actorName.trim(),
        'actorAvatarUrl': actorAvatarUrl.trim(),
        'title': title.trim(),
        'message': message.trim(),
        'imageUrl': imageUrl.trim(),
        'route': route.trim(),
        'createdAtMs': DateTime.now().millisecondsSinceEpoch,
      }).timeout(const Duration(seconds: 12));
    } catch (_) {
      // Best-effort — never block the action (follow, post) that triggered
      // this notification over a failed inbox write.
    }
  }

  /// Call right after a successful follow — writes into the TARGET's
  /// inbox (the person who was just followed).
  Future<void> addNewFollowerNotification({
    required String targetUserId,
    required String actorId,
    required String actorName,
    String actorAvatarUrl = '',
  }) {
    return _addNotification(
      targetUserId: targetUserId,
      type: 'new_follower',
      actorId: actorId,
      actorName: actorName,
      actorAvatarUrl: actorAvatarUrl,
      title: 'New follower',
      message:
          '${actorName.trim().isEmpty ? 'Someone' : actorName.trim()} started following you.',
      // /team/{id} is this app's public user-profile route — "team" is
      // just an indirection over a user's profile, not a separate
      // aggregate (see route_resolver.dart's 'team' case).
      route: '/team/${actorId.trim()}',
    );
  }

  /// Call once per follower right after an organizer posts an
  /// announcement — writes into each FOLLOWER's inbox.
  Future<void> addOrganizerAnnouncementNotification({
    required String targetUserId,
    required String masterLeagueId,
    required String actorId,
    required String actorName,
    String actorAvatarUrl = '',
    required String title,
    required String message,
  }) {
    return _addNotification(
      targetUserId: targetUserId,
      type: 'organizer_announcement',
      actorId: actorId,
      actorName: actorName,
      actorAvatarUrl: actorAvatarUrl,
      title: title,
      message: message,
      route: '/master-leagues/${masterLeagueId.trim()}',
    );
  }
}
