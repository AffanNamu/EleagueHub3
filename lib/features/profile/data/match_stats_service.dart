//lib/features/profile/data/match_stats_service.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Writes match-result side effects into a user's profile subtree:
///   users/{uid}/recent_matches/{matchId}
///   users/{uid}/stats/summary  (wins/draws/losses/goals incremented)
///
/// This is intentionally best-effort and non-fatal — called AFTER the
/// authoritative score write (team aggregates / match doc) has already
/// committed, exactly like the existing post-hoc membership writes in
/// LocalLeaguesRepository.saveTeams. A failure here must never surface
/// to the organizer as a score-update error.
class MatchStatsService {
  MatchStatsService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  bool _looksLikeFirebaseUid(String s) => s.trim().length > 20;

  /// Records the outcome of one finished match for both team owners
  /// (when their team id is a real Firebase uid — teams not tied to a
  /// real account are skipped, since there's no user doc to write to).
  ///
  /// [matchId] is used as the recent_matches doc id so re-scoring a
  /// match (correction) overwrites the cached entry instead of
  /// duplicating it and double-counting stats — see the delta logic
  /// below, which reads any existing cached entry first and only
  /// applies the difference to the stats counters.
  Future<void> recordMatchResult({
    required String leagueId,
    required String leagueName,
    required String matchId,
    required String homeTeamId,
    required String homeTeamName,
    required String awayTeamId,
    required String awayTeamName,
    required int homeScore,
    required int awayScore,
    required int playedAtMs,
  }) async {
    await Future.wait([
      _recordForSide(
        leagueId: leagueId,
        leagueName: leagueName,
        matchId: matchId,
        ownerCandidateId: homeTeamId,
        opponentName: awayTeamName,
        goalsFor: homeScore,
        goalsAgainst: awayScore,
        playedAtMs: playedAtMs,
      ),
      _recordForSide(
        leagueId: leagueId,
        leagueName: leagueName,
        matchId: matchId,
        ownerCandidateId: awayTeamId,
        opponentName: homeTeamName,
        goalsFor: awayScore,
        goalsAgainst: homeScore,
        playedAtMs: playedAtMs,
      ),
    ]);
  }

  Future<void> _recordForSide({
    required String leagueId,
    required String leagueName,
    required String matchId,
    required String ownerCandidateId,
    required String opponentName,
    required int goalsFor,
    required int goalsAgainst,
    required int playedAtMs,
  }) async {
    final uid = ownerCandidateId.trim();
    if (!_looksLikeFirebaseUid(uid)) return;

    try {
      final matchRef = _users.doc(uid).collection('recent_matches').doc(matchId);
      final statsRef = _users.doc(uid).collection('stats').doc('summary');

      final newResult =
          goalsFor > goalsAgainst ? 'W' : (goalsFor == goalsAgainst ? 'D' : 'L');

      await _firestore.runTransaction((txn) async {
        final existingMatchSnap = await txn.get(matchRef);
        final existingStatsSnap = await txn.get(statsRef);
        final existingStats = existingStatsSnap.data() ?? <String, dynamic>{};

        int wins = _asInt(existingStats['wins']);
        int draws = _asInt(existingStats['draws']);
        int losses = _asInt(existingStats['losses']);
        int gf = _asInt(existingStats['goalsScored']);
        int ga = _asInt(existingStats['goalsConceded']);

        // If this match was already recorded (correction/re-score),
        // subtract the old contribution before applying the new one so
        // counters never double-count.
        if (existingMatchSnap.exists) {
          final old = existingMatchSnap.data() ?? <String, dynamic>{};
          final oldResult = (old['result'] as String? ?? '').trim();
          final oldGf = _asInt(old['goalsFor']);
          final oldGa = _asInt(old['goalsAgainst']);

          if (oldResult == 'W') wins = (wins - 1).clamp(0, 1 << 31);
          if (oldResult == 'D') draws = (draws - 1).clamp(0, 1 << 31);
          if (oldResult == 'L') losses = (losses - 1).clamp(0, 1 << 31);
          gf = (gf - oldGf).clamp(0, 1 << 31);
          ga = (ga - oldGa).clamp(0, 1 << 31);
        }

        if (newResult == 'W') wins += 1;
        if (newResult == 'D') draws += 1;
        if (newResult == 'L') losses += 1;
        gf += goalsFor;
        ga += goalsAgainst;

        txn.set(
          matchRef,
          <String, dynamic>{
            'leagueId': leagueId,
            'leagueName': leagueName,
            'opponentName': opponentName,
            'result': newResult,
            'goalsFor': goalsFor,
            'goalsAgainst': goalsAgainst,
            'playedAtMs': playedAtMs,
          },
        );

        txn.set(
          statsRef,
          <String, dynamic>{
            'wins': wins,
            'draws': draws,
            'losses': losses,
            'goalsScored': gf,
            'goalsConceded': ga,
          },
          SetOptions(merge: true),
        );
      }).timeout(const Duration(seconds: 15));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MatchStatsService] recordMatchResult failed for $uid (non-fatal): $e');
      }
    }
  }

  /// Call once when a user successfully joins or creates a league —
  /// increments their competitionsJoined counter. Best-effort.
  Future<void> incrementCompetitionsJoined(String userId) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;

    try {
      final statsRef = _users.doc(uid).collection('stats').doc('summary');
      await _firestore.runTransaction((txn) async {
        final snap = await txn.get(statsRef);
        final current = _asInt((snap.data() ?? {})['competitionsJoined']);
        txn.set(
          statsRef,
          {'competitionsJoined': current + 1},
          SetOptions(merge: true),
        );
      }).timeout(const Duration(seconds: 12));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MatchStatsService] incrementCompetitionsJoined failed (non-fatal): $e');
      }
    }
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}
