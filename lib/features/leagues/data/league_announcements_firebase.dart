import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/league_announcement.dart';

class LeagueAnnouncementsFirebase {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  CollectionReference get _annCol => _firestore.collection('announcements');

  Stream<List<LeagueAnnouncement>> watchLeagueAnnouncements(String leagueId) {
    return _annCol
        .where('leagueId', isEqualTo: leagueId)
        .orderBy('createdAtMs', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => LeagueAnnouncement.fromJson(doc.data() as Map<String, dynamic>))
            .toList());
  }

  Future<void> addAnnouncement(LeagueAnnouncement announcement) async {
    final id = announcement.id.isEmpty ? _uuid.v4() : announcement.id;
    await _annCol.doc(id).set(announcement.copyWith(id: id).toJson());
  }

  Future<void> deleteAnnouncement(String id) async {
    await _annCol.doc(id).delete();
  }
}
