import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/connectivity_service.dart';
import '../models/point_adjustment.dart';

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

  Future<void> _requireOnline() async {
    await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));
  }

  /// Server-authoritative organizer/owner check.
  ///
  /// SECURITY NOTE:
  /// - This is a *client-side guard* only. Production security must be enforced
  ///   with Firestore Security Rules (see firestore.rules.example).
  /// - Your app also has app-level ADMIN role logic; when you paste those files,
  ///   we will upgrade this to check ADMIN role explicitly (as required).
  Future<void> _requireLeagueAdminOrThrow(String leagueId) async {
    final authUid = _requireAuthUid();
    await _requireOnline();

    final snap = await _firestore
        .collection('leagues')
        .doc(leagueId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));

    if (!snap.exists) {
      throw const UserFriendlyException("We couldn't find this league. Please refresh and try again.");
    }

    final data = snap.data() ?? <String, dynamic>{};
    final organizerUid = (data['organizerUid'] as String? ?? '').trim();
    final ownerUid = (data['ownerUid'] as String? ?? '').trim();

    final ok = (organizerUid.isNotEmpty && organizerUid == authUid) || (ownerUid.isNotEmpty && ownerUid == authUid);
    if (!ok) {
      throw const UserFriendlyException('You don\u2019t have permission to do that right now.');
    }
  }

  CollectionReference<Map<String, dynamic>> _matchesCol(String leagueId) {
    return _firestore.collection('leagues').doc(leagueId).collection('matches');
  }

  CollectionReference<Map<String, dynamic>> _pointAdjustmentsCol(String leagueId) {
    return _firestore.collection('leagues').doc(leagueId).collection('pointAdjustments');
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
      await _requireOnline();

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

  /// ADMIN POINT ADJUSTMENT (production-ready write path):
  ///
  /// - Creates an immutable audit-log document in:
  ///     leagues/{leagueId}/pointAdjustments/{adjustmentId}
  /// - Updates the team aggregate fields:
  ///     adminAdjustment, finalPoints
  ///
  /// SECURITY CONSIDERATIONS:
  /// - Must be protected by Firestore rules so only ADMIN can create adjustments.
  /// - Rules should also enforce: finalPoints == basePoints + adminAdjustment
  ///   to prevent arbitrary finalPoints overwrites.
  Future<void> createPointAdjustment({
    required String leagueId,
    required String teamId,
    required PointAdjustmentType type,
    required int points,
    required String reason,
  }) async {
    try {
      final uid = _requireAuthUid();
      await _requireLeagueAdminOrThrow(leagueId);

      final p = points;
      if (p <= 0) {
        throw const UserFriendlyException('Points must be greater than 0.');
      }

      final r = reason.trim();
      if (r.isEmpty) {
        throw const UserFriendlyException('A reason is required.');
      }

      final delta = type == PointAdjustmentType.addition ? p : -p;

      final leagueRef = _firestore.collection('leagues').doc(leagueId);
      final teamRef = leagueRef.collection('teams').doc(teamId);
      final adjRef = _pointAdjustmentsCol(leagueId).doc();

      await _firestore.runTransaction((txn) async {
        final teamSnap = await txn.get(teamRef);
        if (!teamSnap.exists) {
          throw const UserFriendlyException("We couldn't find this team. Please refresh and try again.");
        }

        final teamData = (teamSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final basePoints = (teamData['basePoints'] as num?)?.toInt() ?? 0;
        final currentAdj = (teamData['adminAdjustment'] as num?)?.toInt() ?? 0;

        final newAdj = currentAdj + delta;
        final newFinal = basePoints + newAdj;

        // Immutable audit log.
        txn.set(adjRef, <String, dynamic>{
          'teamId': teamId,
          'type': type.toFirestoreString(),
          'points': p,
          'reason': r,
          'adjustedBy': uid,
          // Use server time; rules can enforce createdAt == request.time.
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Aggregate fields for scalable standings rendering.
        txn.set(teamRef, <String, dynamic>{
          'adminAdjustment': newAdj,
          'finalPoints': newFinal,
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        }, SetOptions(merge: true));
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      if (e is UserFriendlyException) rethrow;
      throw const UserFriendlyException("We couldn't adjust points right now. Please try again.");
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
