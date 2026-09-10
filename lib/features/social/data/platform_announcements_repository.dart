// lib/features/social/data/platform_announcements_repository.dart
//
// Reads platform_announcements/{id} — the collection defined in
// firestore.rules (public read, isSuperAdmin()-only write via the mobile
// app; the web admin workspace writes here too via a server-side Admin
// SDK path that intentionally bypasses that rule, same delegation
// precedent as global_chat_requests.review elsewhere in this codebase).
//
// Schema (defined here — the rules file has no field validation on this
// collection, it's intentionally open):
//   id: string
//   title: string
//   message: string
//   severity: string ('info' | 'warning' | 'critical')
//   active: bool
//   createdAtMs: int
//   createdBy: string (admin uid)
//
// Unread tracking: users/{uid}.lastSeenAnnouncementAtMs (int, ms epoch).
// An announcement counts as unread if createdAtMs > lastSeenAnnouncementAtMs.
// markAllSeen() bumps that field to "now" when the user opens the
// notification list. This is a single per-user cursor, not per-item
// read state — simplest model that still gives an accurate unread count.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PlatformAnnouncement {
  const PlatformAnnouncement({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.createdAtMs,
  });

  final String id;
  final String title;
  final String message;
  final String severity;
  final int createdAtMs;

  factory PlatformAnnouncement.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return PlatformAnnouncement(
      id: doc.id,
      title: (data['title'] as String? ?? '').trim(),
      message: (data['message'] as String? ?? '').trim(),
      severity: (data['severity'] as String? ?? 'info').trim(),
      createdAtMs:
          data['createdAtMs'] is int ? data['createdAtMs'] as int : 0,
    );
  }
}

class PlatformAnnouncementsRepository {
  PlatformAnnouncementsRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const int _recentLimit = 30;

  /// Streams up to the 30 most recent active announcements, newest first.
  /// Used by the notification list screen.
  Stream<List<PlatformAnnouncement>> watchRecent() {
    return _firestore
        .collection('platform_announcements')
        .where('active', isEqualTo: true)
        .orderBy('createdAtMs', descending: true)
        .limit(_recentLimit)
        .snapshots()
        .map<List<PlatformAnnouncement>>(
      (snap) => snap.docs.map(PlatformAnnouncement.fromDoc).toList(),
    ).handleError((Object _, StackTrace __) => <PlatformAnnouncement>[]);
  }

  /// Streams the current user's unread count against the same recent
  /// window used by [watchRecent] — capped at 9+ display by the caller,
  /// not here (this returns the real count).
  Stream<int> watchUnreadCount() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return Stream<int>.value(0);

    final userDocStream =
        _firestore.collection('users').doc(uid).snapshots();

    return userDocStream.asyncExpand<int>((userDoc) {
      final lastSeenAtMs =
          userDoc.data()?['lastSeenAnnouncementAtMs'] is int
              ? userDoc.data()!['lastSeenAnnouncementAtMs'] as int
              : 0;

      return watchRecent().map<int>(
        (items) =>
            items.where((a) => a.createdAtMs > lastSeenAtMs).length,
      );
    }).handleError((Object _, StackTrace __) => 0);
  }

  /// Marks all currently-visible announcements as seen by bumping the
  /// per-user cursor to now. Best-effort — a failure here should never
  /// block the notification list from opening.
  Future<void> markAllSeen() async {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    try {
      await _firestore.collection('users').doc(uid).set(
        <String, dynamic>{
          'lastSeenAnnouncementAtMs': DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }
}
