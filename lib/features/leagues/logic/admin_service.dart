import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/connectivity_service.dart';

/// User-safe exception: if UI accidentally shows `$e`, it will still be a friendly message.
class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

/// ONLINE-ONLY Admin service.
///
/// This replaces the legacy SQLite/offline-sync implementation.
/// All writes go directly to Firestore, and reads come from Firestore.
/// No local persistence, no background sync, no unsynced queues.
class AdminService {
  AdminService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String _requireAuthUid() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const UserFriendlyException('Please sign in and try again.');
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _matchesCol(String leagueId) {
    return _firestore.collection('leagues').doc(leagueId).collection('matches');
  }

  /// Legacy signature kept for compatibility with older call sites.
  ///
  /// IMPORTANT:
  /// - Firestore match document IDs are typically strings (UUIDs).
  /// - This method uses `matchId.toString()` as the doc id.
  /// - Prefer using [updateScoreByDocId] in newer code paths.
  Future<void> updateScore(int matchId, int hScore, int aScore, String leagueId) async {
    await updateScoreByDocId(
      leagueId: leagueId,
      matchDocId: matchId.toString(),
      homeScore: hScore,
      awayScore: aScore,
    );
  }

  /// Preferred method: update a match score by Firestore document id.
  ///
  /// Notes:
  /// - We only update score fields + updatedAtMs to avoid breaking existing schema.
  /// - Status is intentionally not forced here because different deployments
  ///   may store it as int or string; higher-level flows usually update full
  ///   match docs via repositories/models.
  Future<void> updateScoreByDocId({
    required String leagueId,
    required String matchDocId,
    required int homeScore,
    required int awayScore,
  }) async {
    try {
      _requireAuthUid();
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final h = homeScore < 0 ? 0 : homeScore;
      final a = awayScore < 0 ? 0 : awayScore;

      final ref = _matchesCol(leagueId).doc(matchDocId.trim());
      final snap = await ref.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 12));
      if (!snap.exists) {
        throw const UserFriendlyException("We couldn't find this match. Please refresh and try again.");
      }

      await ref.set(
        <String, dynamic>{
          'homeScore': h,
          'awayScore': a,
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      if (e is UserFriendlyException) rethrow;
      throw const UserFriendlyException("We couldn't update the score right now. Please try again.");
    }
  }

  /// ONLINE-ONLY: unsynced local matches do not exist anymore.
  /// Kept for compatibility; always returns empty.
  Future<List<Map<String, dynamic>>> getUnsyncedMatches() async {
    return const <Map<String, dynamic>>[];
  }

  /// ONLINE-ONLY: background/offline sync is removed.
  /// Kept for compatibility; this is a no-op.
  Future<void> syncScoresOnline(Future<bool> Function(Map<String, dynamic>) uploadMatch) async {
    return;
  }
}
