import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Awards a trophy to a user for finishing a competition, and keeps
/// their cached stats.trophies counter in sync. Called by organizer
/// flows once a league's final standings are confirmed (e.g. wired
/// into the existing "Compute Winner" action).
class TrophyService {
  TrophyService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  bool _looksLikeFirebaseUid(String s) => s.trim().length > 20;

  /// [teamOwnerId] should be the winning team's ownerId (Team.ownerId).
  /// No-op if that id isn't a real Firebase uid (team not tied to an
  /// account). [trophyId] should be deterministic per league+season so
  /// re-running standings computation doesn't create duplicate trophies —
  /// e.g. '${leagueId}_final'.
  Future<void> awardTrophy({
    required String teamOwnerId,
    required String trophyId,
    required String leagueId,
    required String leagueName,
    required int position,
    required String season,
  }) async {
    final uid = teamOwnerId.trim();
    if (!_looksLikeFirebaseUid(uid)) return;

    try {
      final trophyRef = _users.doc(uid).collection('trophies').doc(trophyId);
      final statsRef = _users.doc(uid).collection('stats').doc('summary');

      await _firestore.runTransaction((txn) async {
        final existing = await txn.get(trophyRef);
        if (existing.exists) return; // already awarded, don't double-count

        txn.set(trophyRef, <String, dynamic>{
          'leagueId': leagueId,
          'leagueName': leagueName,
          'position': position,
          'season': season,
          'createdAtMs': DateTime.now().millisecondsSinceEpoch,
        });

        final statsSnap = await txn.get(statsRef);
        final current = _asInt((statsSnap.data() ?? {})['trophies']);
        txn.set(
          statsRef,
          {'trophies': current + 1},
          SetOptions(merge: true),
        );
      }).timeout(const Duration(seconds: 15));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[TrophyService] awardTrophy failed for $uid (non-fatal): $e');
      }
    }
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}
