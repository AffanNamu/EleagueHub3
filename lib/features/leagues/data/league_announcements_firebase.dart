import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/league_announcement.dart';

/// Firestore-backed announcements for master league workspaces.
class LeagueAnnouncementsFirebase {
  LeagueAnnouncementsFirebase();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Master-league announcement collection path ──────────────────────────
  CollectionReference<Map<String, dynamic>> _masterCol(String masterLeagueId) =>
      _db
          .collection('master_leagues')
          .doc(masterLeagueId.trim())
          .collection('announcements');

  // ── Watch all announcements (ordered newest first) ──────────────────────
  Stream<List<LeagueAnnouncement>> watchMasterLeagueAnnouncements(
    String masterLeagueId,
  ) {
    if (masterLeagueId.trim().isEmpty) {
      return Stream.value(const <LeagueAnnouncement>[]);
    }

    return _masterCol(masterLeagueId)
        .orderBy('createdAtMs', descending: true)
        .snapshots(includeMetadataChanges: false)
        .map((snap) {
          final list = <LeagueAnnouncement>[];
          for (final doc in snap.docs) {
            try {
              final data = <String, dynamic>{...doc.data(), 'id': doc.id};
              list.add(LeagueAnnouncement.fromMap(data));
            } catch (e) {
              // skip malformed docs
            }
          }
          return list;
        })
        .handleError((Object e) {
          return <LeagueAnnouncement>[];
        });
  }

  // ── Watch the single pinned announcement ────────────────────────────────
  Stream<LeagueAnnouncement?> watchPinnedMasterLeagueAnnouncement(
    String masterLeagueId,
  ) {
    if (masterLeagueId.trim().isEmpty) {
      return Stream.value(null);
    }

    return _masterCol(masterLeagueId)
        .where('pinned', isEqualTo: true)
        .limit(1)
        .snapshots(includeMetadataChanges: false)
        .map((snap) {
          if (snap.docs.isEmpty) return null;
          try {
            final doc = snap.docs.first;
            final data = <String, dynamic>{...doc.data(), 'id': doc.id};
            return LeagueAnnouncement.fromMap(data);
          } catch (_) {
            return null;
          }
        })
        .handleError((Object e) {
          return null;
        });
  }

  // ── Add a new master league announcement ────────────────────────────────
  Future<void> addMasterLeagueAnnouncement({
    required String masterLeagueId,
    required String title,
    required String message,
    required String authorId,
    required String authorName,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final data = <String, dynamic>{
      'masterLeagueId': masterLeagueId.trim(),
      'leagueId': '',
      'title': title.trim(),
      'message': message.trim(),
      'authorId': authorId.trim(),
      'authorName': authorName.trim(),
      'pinned': false,
      'pinnedBy': '',
      'pinnedAtMs': 0,
      'createdAtMs': now,
      'updatedAtMs': now,
    };

    await _masterCol(masterLeagueId).add(data);
  }

  // ── Pin an announcement ─────────────────────────────────────────────────
  Future<void> pinMasterLeagueAnnouncement({
    required String masterLeagueId,
    required String announcementId,
    required String pinnedBy,
  }) async {
    // First unpin any existing pinned announcements
    final existing = await _masterCol(masterLeagueId)
        .where('pinned', isEqualTo: true)
        .get();

    final batch = _db.batch();
    for (final doc in existing.docs) {
      batch.update(doc.reference, <String, dynamic>{
        'pinned': false,
        'pinnedBy': '',
        'pinnedAtMs': 0,
      });
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    batch.update(
      _masterCol(masterLeagueId).doc(announcementId),
      <String, dynamic>{
        'pinned': true,
        'pinnedBy': pinnedBy.trim(),
        'pinnedAtMs': now,
      },
    );

    await batch.commit();
  }

  // ── Unpin an announcement ───────────────────────────────────────────────
  Future<void> unpinMasterLeagueAnnouncement({
    required String announcementId,
    required String masterLeagueId,
  }) async {
    await _masterCol(masterLeagueId)
        .doc(announcementId)
        .update(<String, dynamic>{
      'pinned': false,
      'pinnedBy': '',
      'pinnedAtMs': 0,
    });
  }

  // ── Delete an announcement ──────────────────────────────────────────────
  Future<void> deleteAnnouncement(
    String announcementId, {
    required String masterLeagueId,
  }) async {
    await _masterCol(masterLeagueId).doc(announcementId).delete();
  }
}