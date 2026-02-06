import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/league.dart';

class LeaguesRepositoryFirebase {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  CollectionReference get _leaguesCol => _firestore.collection('leagues');

  League _docToLeague(QueryDocumentSnapshot doc) {
    final raw = (doc.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final map = <String, dynamic>{...raw};

    // Ensure id is always present (some Firestore docs won't include an 'id' field).
    final existingId = (map['id'] as String?)?.trim() ?? '';
    if (existingId.isEmpty) {
      map['id'] = doc.id;
    }

    return League.fromRemoteMap(map);
  }

  League _snapToLeague(DocumentSnapshot doc) {
    final raw = (doc.data() as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final map = <String, dynamic>{...raw};

    final existingId = (map['id'] as String?)?.trim() ?? '';
    if (existingId.isEmpty) {
      map['id'] = doc.id;
    }

    return League.fromRemoteMap(map);
  }

  Future<List<League>> getAllLeagues() async {
    final snapshot = await _leaguesCol.get();
    return snapshot.docs
        .whereType<QueryDocumentSnapshot>()
        .map(_docToLeague)
        .toList();
  }

  Stream<List<League>> watchLeagues() {
    return _leaguesCol.snapshots().map(
          (snapshot) => snapshot.docs
              .whereType<QueryDocumentSnapshot>()
              .map(_docToLeague)
              .toList(),
        );
  }

  Future<League?> getLeagueById(String id) async {
    final doc = await _leaguesCol.doc(id).get();
    if (!doc.exists) return null;
    return _snapToLeague(doc);
  }

  Future<void> saveLeague(League league) async {
    final id = league.id.isEmpty ? _uuid.v4() : league.id;
    await _leaguesCol.doc(id).set(league.copyWith(id: id).toJson());
  }

  Future<void> deleteLeague(String leagueId) async {
    await _leaguesCol.doc(leagueId).delete();
  }
}
