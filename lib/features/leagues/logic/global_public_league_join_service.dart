import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/leagues_repository_local.dart';
import '../domain/models/global_public_league.dart';
import '../models/league.dart';
import '../models/membership.dart';

enum GlobalPublicLeagueJoinStatus {
  joined,
  alreadyJoined,
  full,
  privateLeague,
  finished,
}

class GlobalPublicLeagueJoinResult {
  final GlobalPublicLeagueJoinStatus status;
  final League? league;

  const GlobalPublicLeagueJoinResult({
    required this.status,
    required this.league,
  });
}

/// Production-oriented join service:
/// - Any user can join a PUBLIC league as:
///   - participant: consumes capacity (registeredCount++)
///   - viewer: does NOT consume capacity
/// - Participant join uses a Firestore transaction to enforce capacity safely.
/// - Viewer join adds the user to memberIds for access, without creating a membership doc.
/// - Best-effort sync into local storage via existing LocalLeaguesRepository join-by-code.
class GlobalPublicLeagueJoinService {
  GlobalPublicLeagueJoinService({
    required FirebaseFirestore firestore,
    required LocalLeaguesRepository localRepo,
  })  : _firestore = firestore,
        _localRepo = localRepo;

  final FirebaseFirestore _firestore;
  final LocalLeaguesRepository _localRepo;

  Future<GlobalPublicLeagueJoinResult> joinPublicLeague({
    required GlobalPublicLeague league,
    required String userId,
    required LeagueJoinMode mode,
  }) async {
    final leagueId = league.league.id.trim();
    if (leagueId.isEmpty) {
      throw ArgumentError('league.id is required');
    }

    // Always require a join code for local sync (existing architecture).
    final joinCode = league.league.code.trim();
    if (joinCode.isEmpty) {
      throw StateError('League Join ID is missing.');
    }

    final leagueRef = _firestore.collection('leagues').doc(leagueId);
    final membershipsRef = leagueRef.collection('memberships').doc(userId);

    final now = DateTime.now().millisecondsSinceEpoch;

    final GlobalPublicLeagueJoinStatus status = await _firestore.runTransaction((tx) async {
      final snap = await tx.get(leagueRef);
      final data = (snap.data() ?? <String, dynamic>{});

      final isPrivate = data['isPrivate'] == 1 || data['isPrivate'] == true;
      if (isPrivate) {
        return GlobalPublicLeagueJoinStatus.privateLeague;
      }

      final isFinished = data['isFinished'] == true || data['isFinished'] == 1;
      if (isFinished) {
        return GlobalPublicLeagueJoinStatus.finished;
      }

      final memberIdsRaw = data['memberIds'];
      final memberIds = (memberIdsRaw is List)
          ? memberIdsRaw.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toSet()
          : <String>{};

      // Idempotency: if user already has access, don't re-join / re-count.
      if (memberIds.contains(userId)) {
        return GlobalPublicLeagueJoinStatus.alreadyJoined;
      }

      // VIEWER JOIN: do not touch counts, do not create membership.
      if (mode == LeagueJoinMode.viewer) {
        tx.set(
          leagueRef,
          <String, dynamic>{
            'memberIds': FieldValue.arrayUnion([userId]),
            'updatedAtMs': now,
          },
          SetOptions(merge: true),
        );
        return GlobalPublicLeagueJoinStatus.joined;
      }

      // PARTICIPANT JOIN
      final maxTeams = (data['maxTeams'] as num?)?.toInt() ?? league.league.maxTeams;

      final isFullStored = data['isFull'] == true || data['isFull'] == 1;

      final registeredCount = (data['registeredCount'] as num?)?.toInt() ?? (league.registeredCount ?? 0);

      if (isFullStored || registeredCount >= maxTeams) {
        // Keep `isFull` consistent for the rest of the app.
        tx.set(
          leagueRef,
          <String, dynamic>{
            'isFull': true,
            'updatedAtMs': now,
          },
          SetOptions(merge: true),
        );
        return GlobalPublicLeagueJoinStatus.full;
      }

      // If membership doc exists, treat as already joined (but ensure memberIds contains user).
      final membershipSnap = await tx.get(membershipsRef);
      if (membershipSnap.exists) {
        tx.set(
          leagueRef,
          <String, dynamic>{
            'memberIds': FieldValue.arrayUnion([userId]),
            'updatedAtMs': now,
          },
          SetOptions(merge: true),
        );
        return GlobalPublicLeagueJoinStatus.alreadyJoined;
      }

      final nextCount = registeredCount + 1;
      final nextIsFull = nextCount >= maxTeams;

      // Write membership with deterministic docId=userId for idempotency.
      tx.set(
        membershipsRef,
        <String, dynamic>{
          'id': userId,
          'leagueId': leagueId,
          'userId': userId,
          'teamId': null,
          'role': LeagueRole.member.index,
          'updatedAtMs': now,
          'version': 1,
        },
        SetOptions(merge: true),
      );

      // Update league doc counts + access.
      tx.set(
        leagueRef,
        <String, dynamic>{
          'registeredCount': nextCount,
          'isFull': nextIsFull,
          'memberIds': FieldValue.arrayUnion([userId]),
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      );

      return GlobalPublicLeagueJoinStatus.joined;
    });

    if (status == GlobalPublicLeagueJoinStatus.full ||
        status == GlobalPublicLeagueJoinStatus.privateLeague ||
        status == GlobalPublicLeagueJoinStatus.finished) {
      return GlobalPublicLeagueJoinResult(status: status, league: null);
    }

    // Best-effort local sync using existing code path (DO NOT modify legacy join flows).
    League? syncedLeague;
    try {
      syncedLeague = await _localRepo.joinLeagueLocallyByCode(
        joinCode: joinCode,
        userId: userId,
        mode: mode,
        placeholderBuilder: (generatedLeagueId) {
          // Only used on transient network failures.
          return league.league.copyWith(
            id: generatedLeagueId,
            updatedAtMs: now,
          );
        },
      );
    } catch (_) {
      // Non-fatal: remote join succeeded; local cache will be updated on next sync/refresh.
    }

    return GlobalPublicLeagueJoinResult(
      status: status,
      league: syncedLeague ?? league.league,
    );
  }
}
