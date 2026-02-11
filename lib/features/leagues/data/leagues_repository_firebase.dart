import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../models/league.dart';

class LeaguesRepositoryFirebase {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> get _leaguesCol => _firestore.collection('leagues');

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
  /// - Rules authority is FirebaseAuth UID only.
  /// - This method must always write organizerUid/ownerUid = request.auth.uid.
  /// - Ensure memberIds contains request.auth.uid.
  Future<void> saveLeague(League league) async {
    final authUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (authUid.isEmpty) {
      throw StateError('Not signed in (FirebaseAuth.currentUser == null)');
    }

    final id = league.id.isEmpty ? _uuid.v4() : league.id;

    final fixed = league.copyWith(
      id: id,
      organizerUid: authUid,
      code: league.code.trim().toUpperCase(),
    );

    await _leaguesCol.doc(id).set(
      {
        ...fixed.toJson(),

        // Rules-authoritative owner fields
        'organizerUid': authUid,
        'ownerUid': authUid,

        // Back-compat but must be Firebase UID if present
        'ownerId': authUid,

        // Membership must contain ONLY Firebase UIDs (never short/share ids).
        'memberIds': FieldValue.arrayUnion([authUid]),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> deleteLeague(String leagueId) async {
    await _leaguesCol.doc(leagueId).delete();
  }
}
