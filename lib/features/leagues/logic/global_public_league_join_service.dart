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
/// - Joins a PUBLIC league for any global user.
/// - Enforces capacity using a denormalized `registeredCount` field when present.
/// - Sets `isFull=true` when capacity is reached so the global list removes it automatically.
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
    final baselineCount = league.registeredCount ?? 0;

    final GlobalPublicLeagueJoinStatus status = await _firestore.runTransaction((tx) async {
      final snap = await tx.get(leagueRef);
      final data = (snap.data() ?? <String, dynamic>{});

      final isPrivate = data['isPrivate'] == 1 || data['isPrivate'] == true;
      if (isPrivate) {
        return GlobalPublicLeagueJoinStatus.privateLeague;
      }

      final memberIdsRaw = data['memberIds'];
      final memberIds = (memberIdsRaw is List)
          ? memberIdsRaw.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toSet()
          : <String>{};

      // Idempotency: if user is already a member/viewer, do not increment counts.
      if (memberIds.contains(userId)) {
        return GlobalPublicLeagueJoinStatus.alreadyJoined;
      }

      final maxTeams = (data['maxTeams'] as num?)?.toInt() ?? league.league.maxTeams;

      final isFullStored = data['isFull'] == true || data['isFull'] == 1;

      final registeredCount = (data['registeredCount'] as num?)?.toInt() ?? baselineCount;

      if (isFullStored || registeredCount >= maxTeams) {
        // Ensure it disappears globally going forward.
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

      final membershipSnap = await tx.get(membershipsRef);
      if (membershipSnap.exists) {
        // Membership doc already exists but memberIds may not; ensure memberIds contains user.
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

      // Write membership with deterministic docId=userId for idempotency in this join path.
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

      // Update league doc counts + full flag.
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

    if (status == GlobalPublicLeagueJoinStatus.full || status == GlobalPublicLeagueJoinStatus.privateLeague) {
      return GlobalPublicLeagueJoinResult(status: status, league: null);
    }

    // Best-effort local sync using existing code path (DO NOT modify legacy join flows).
    // This keeps the user's "My Leagues" tab consistent.
    League? syncedLeague;
    try {
      syncedLeague = await _localRepo.joinLeagueLocallyByCode(
        joinCode: joinCode,
        userId: userId,
        mode: LeagueJoinMode.participant,
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
