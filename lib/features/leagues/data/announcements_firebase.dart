import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/league_announcement.dart';

class LeagueAnnouncementsFirebase {
  final _collection = FirebaseFirestore.instance.collection('league_announcements');

  Future<void> addAnnouncement(LeagueAnnouncement ann) async {
    await _collection.doc(ann.id).set(ann.toMap());
  }

  Stream<List<LeagueAnnouncement>> watchLeagueAnnouncements(String leagueId) {
    return _collection
        .where('leagueId', isEqualTo: leagueId)
        .orderBy('createdAtMs', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => LeagueAnnouncement.fromMap(d.data())).toList());
  }
}
