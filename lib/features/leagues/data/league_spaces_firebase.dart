import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/league_space.dart';

class LeagueSpacesFirebase {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  CollectionReference get _spacesCol => _firestore.collection('spaces');

  Stream<LeagueSpace?> watchSpace(String leagueId) {
    return _spacesCol
        .where('leagueId', isEqualTo: leagueId)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return LeagueSpace.fromJson(snapshot.docs.first.data() as Map<String, dynamic>);
    });
  }

  Future<LeagueSpace> startSpace({required String leagueId, required String hostUserId, required String title}) async {
    final space = LeagueSpace(
      id: _uuid.v4(),
      leagueId: leagueId,
      hostUserId: hostUserId,
      title: title,
      isLive: true,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _spacesCol.doc(space.id).set(space.toJson());
    return space;
  }

  Future<LeagueSpace> endSpace(String leagueId) async {
    final snapshot = await _spacesCol.where('leagueId', isEqualTo: leagueId).limit(1).get();
    if (snapshot.docs.isEmpty) throw Exception('Space not found');
    final doc = snapshot.docs.first;
    await doc.reference.update({'isLive': false, 'endedAtMs': DateTime.now().millisecondsSinceEpoch});
    return LeagueSpace.fromJson(doc.data() as Map<String, dynamic>);
  }
}
