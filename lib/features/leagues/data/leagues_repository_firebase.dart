import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/league.dart';

class LeaguesRepositoryFirebase {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  CollectionReference get _leaguesCol => _firestore.collection('leagues');

  Future<List<League>> getAllLeagues() async {
    final snapshot = await _leaguesCol.get();
    return snapshot.docs.map((doc) => League.fromJson(doc.data() as Map<String, dynamic>)).toList();
  }

  Stream<List<League>> watchLeagues() {
    return _leaguesCol.snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => League.fromJson(doc.data() as Map<String, dynamic>)).toList());
  }

  Future<League?> getLeagueById(String id) async {
    final doc = await _leaguesCol.doc(id).get();
    if (!doc.exists) return null;
    return League.fromJson(doc.data() as Map<String, dynamic>);
  }

  Future<void> saveLeague(League league) async {
    final id = league.id.isEmpty ? _uuid.v4() : league.id;
    await _leaguesCol.doc(id).set(league.copyWith(id: id).toJson());
  }

  Future<void> deleteLeague(String leagueId) async {
    await _leaguesCol.doc(leagueId).delete();
  }
}
