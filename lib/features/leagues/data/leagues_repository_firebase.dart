import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/league.dart';

class LeaguesRepositoryFirebase {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> get _leaguesCol =>
      _firestore.collection('leagues');

  League _docToLeague(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final raw = doc.data();
    final map = <String, dynamic>{...raw};

    final existingId = (map['id'] as String?)?.trim() ?? '';
    if (existingId.isEmpty) map['id'] = doc.id;

    return League.fromRemoteMap(map);
  }

  League _snapToLeague(DocumentSnapshot<Map<String, dynamic>> doc) {
    final raw = (doc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    final map = <String, dynamic>{...raw};

    final existingId = (map['id'] as String?)?.trim() ?? '';
    if (existingId.isEmpty) map['id'] = doc.id;

    return League.fromRemoteMap(map);
  }

  Future<List<League>> getAllLeagues() async {
    final snapshot = await _leaguesCol.get();
    return snapshot.docs.map(_docToLeague).toList();
  }

  Stream<List<League>> watchLeagues() {
    return _leaguesCol.snapshots().map(
          (snapshot) => snapshot.docs.map(_docToLeague).toList(),
        );
  }

  Future<League?> getLeagueById(String id) async {
    final doc = await _leaguesCol.doc(id).get();
    if (!doc.exists) return null;
    return _snapToLeague(doc);
  }

  /// IMPORTANT:
  /// - Use merge:true so we never wipe server-managed fields (memberIds, counts, etc).
  /// - Ensure organizerUid is present (rules authority).
  Future<void> saveLeague(League league) async {
    final id = league.id.isEmpty ? _uuid.v4() : league.id;

    final organizerUid = league.organizerUid.trim().isNotEmpty
        ? league.organizerUid.trim()
        : (league.organizerUserId.trim().length > 20 ? league.organizerUserId.trim() : '');

    final fixed = league.copyWith(
      id: id,
      organizerUid: organizerUid,
    );

    await _leaguesCol.doc(id).set(
          fixed.toJson(),
          SetOptions(merge: true),
        );
  }

  Future<void> deleteLeague(String leagueId) async {
    await _leaguesCol.doc(leagueId).delete();
  }
}
