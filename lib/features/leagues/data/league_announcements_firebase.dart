import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/supabase_edge_notifications_service.dart';
import '../../master_leagues/data/organizer_feed_firebase.dart';
import '../models/league_announcement.dart';

class LeagueAnnouncementsFirebase {
  LeagueAnnouncementsFirebase({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Uuid _uuid = const Uuid();
  final OrganizerFeedFirebase _feed = OrganizerFeedFirebase();

  CollectionReference<Map<String, dynamic>> get _annCol =>
      _firestore.collection('announcements');

  Stream<List<LeagueAnnouncement>> watchLeagueAnnouncements(String leagueId) {
    return _annCol
        .where('leagueId', isEqualTo: leagueId.trim())
        .orderBy('createdAtMs', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) =>
                LeagueAnnouncement.fromMap((doc.data()).cast<String, dynamic>()))
            .toList(growable: false));
  }

  Stream<List<LeagueAnnouncement>> watchMasterLeagueAnnouncements(
      String masterLeagueId) {
    return _annCol
        .where('scope', isEqualTo: 'master_league')
        .where('masterLeagueId', isEqualTo: masterLeagueId.trim())
        .orderBy('createdAtMs', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) =>
                LeagueAnnouncement.fromMap((doc.data()).cast<String, dynamic>()))
            .toList(growable: false));
  }

  Stream<LeagueAnnouncement?> watchPinnedMasterLeagueAnnouncement(
      String masterLeagueId) {
    return _annCol
        .where('scope', isEqualTo: 'master_league')
        .where('masterLeagueId', isEqualTo: masterLeagueId.trim())
        .where('pinned', isEqualTo: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return LeagueAnnouncement.fromMap(
        (snapshot.docs.first.data()).cast<String, dynamic>(),
      );
    });
  }

  Future<void> addAnnouncement(LeagueAnnouncement announcement) async {
    final id = announcement.id.isEmpty ? _uuid.v4() : announcement.id;
    await _annCol.doc(id).set(
          announcement.copyWith(id: id).toMap(),
        );
  }

  Future<void> addMasterLeagueAnnouncement({
    required String masterLeagueId,
    required String title,
    required String message,
    required String authorId,
    required String authorName,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    final ann = LeagueAnnouncement(
      id: id,
      leagueId: '',
      title: title.trim(),
      message: message.trim(),
      createdAtMs: now,
      authorId: authorId.trim(),
      authorName: authorName.trim(),
      scope: 'master_league',
      masterLeagueId: masterLeagueId.trim(),
      pinned: false,
      pinnedAtMs: 0,
      pinnedBy: '',
    );

    await _annCol.doc(id).set(ann.toMap());

    try {
      await _feed.addAnnouncementPostedEvent(
        masterLeagueId: masterLeagueId,
        actorId: authorId,
        actorName: authorName,
        title: title,
      );
    } catch (_) {}

    try {
      await SupabaseEdgeNotificationsService.instance.notifyFollowedOrganizerUpdate(
        masterLeagueId: masterLeagueId,
        organizerName: authorName,
        title: 'New organizer announcement',
        message: title,
        route: '/master-leagues/${masterLeagueId.trim()}',
        eventType: 'announcement',
        actorId: authorId,
      );
    } catch (_) {}
  }

  Future<void> pinMasterLeagueAnnouncement({
    required String masterLeagueId,
    required String announcementId,
    required String pinnedBy,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final scope = 'master_league';
    final mlId = masterLeagueId.trim();
    final annId = announcementId.trim();
    final adminUid = pinnedBy.trim();

    await _firestore.runTransaction((txn) async {
      final existingPinned = await _annCol
          .where('scope', isEqualTo: scope)
          .where('masterLeagueId', isEqualTo: mlId)
          .where('pinned', isEqualTo: true)
          .get();

      for (final doc in existingPinned.docs) {
        txn.update(doc.reference, <String, dynamic>{
          'pinned': false,
          'pinnedAtMs': 0,
          'pinnedBy': '',
        });
      }

      final targetRef = _annCol.doc(annId);
      final targetSnap = await txn.get(targetRef);
      if (!targetSnap.exists) {
        throw StateError('Announcement not found.');
      }

      txn.update(targetRef, <String, dynamic>{
        'pinned': true,
        'pinnedAtMs': now,
        'pinnedBy': adminUid,
      });
    });
  }

  Future<void> unpinMasterLeagueAnnouncement({
    required String announcementId,
  }) async {
    await _annCol.doc(announcementId.trim()).update(<String, dynamic>{
      'pinned': false,
      'pinnedAtMs': 0,
      'pinnedBy': '',
    });
  }

  Future<void> deleteAnnouncement(String id) async {
    await _annCol.doc(id.trim()).delete();
  }
}
