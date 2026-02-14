import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/league_space.dart';

class LeagueSpacesFirebase {
  final _collection = FirebaseFirestore.instance.collection('league_spaces');

  Future<LeagueSpace> startSpace({
    required String leagueId,
    required String hostUserId,
    required String title,
  }) async {
    final id = _collection.doc().id;
    final now = DateTime.now().millisecondsSinceEpoch;
    final space = LeagueSpace(
      id: id,
      leagueId: leagueId,
      hostUserId: hostUserId,
      title: title,
      isLive: true,
      createdAtMs: now,
    );
    await _collection.doc(id).set(space.toMap());
    return space;
  }

  Future<LeagueSpace?> endSpace(String leagueId) async {
    final snapshot = await _collection
        .where('leagueId', isEqualTo: leagueId)
        .where('isLive', isEqualTo: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final doc = snapshot.docs.first;
    await doc.reference.update({
      'isLive': false,
      'endedAtMs': DateTime.now().millisecondsSinceEpoch,
    });

    return LeagueSpace.fromMap(doc.data());
  }

  Stream<LeagueSpace?> watchSpace(String leagueId) {
    return _collection
        .where('leagueId', isEqualTo: leagueId)
        .where('isLive', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.isEmpty
            ? null
            : LeagueSpace.fromMap(snap.docs.first.data()));
  }
}
