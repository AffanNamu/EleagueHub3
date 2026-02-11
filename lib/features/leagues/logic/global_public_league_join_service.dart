import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

/// Join service for PUBLIC leagues.
///
/// IMPORTANT (rules):
/// - All authorization is via FirebaseAuth UID (`request.auth.uid`).
/// - `memberIds` MUST contain ONLY Firebase UIDs and MUST include `request.auth.uid`.
/// - Do NOT write short/share IDs into `memberIds`.
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
    required String userId, // legacy/display only; cloud writes use auth uid
    required LeagueJoinMode mode,
  }) async {
    final leagueId = league.league.id.trim();
    if (leagueId.isEmpty) {
      throw ArgumentError('league.id is required');
    }

    final joinCode = league.league.code.trim();
    if (joinCode.isEmpty) {
      throw StateError('League Join ID is missing.');
    }

    // RULES AUTHORITY
    final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (authUid.isEmpty) {
      throw StateError('Not signed in (FirebaseAuth.currentUser == null).');
    }

    final leagueRef = _firestore.collection('leagues').doc(leagueId);

    // Deterministic membership doc id by auth uid
    final membershipsRef = leagueRef.collection('memberships').doc(authUid);

    final wallNow = DateTime.now().millisecondsSinceEpoch;

    final GlobalPublicLeagueJoinStatus status = await _firestore.runTransaction((tx) async {
      final snap = await tx.get(leagueRef);
      final data = (snap.data() ?? <String, dynamic>{});

      // Ensure updatedAtMs strictly increases to satisfy rules that use ">"
      final prevUpdatedAtMs = (data['updatedAtMs'] as num?)?.toInt() ?? 0;
      final now = (wallNow > prevUpdatedAtMs) ? wallNow : (prevUpdatedAtMs + 1);

      final isPrivate = data['isPrivate'] == 1 || data['isPrivate'] == true;
      if (isPrivate) return GlobalPublicLeagueJoinStatus.privateLeague;

      final isFinished = data['isFinished'] == true || data['isFinished'] == 1;
      if (isFinished) return GlobalPublicLeagueJoinStatus.finished;

      final memberIdsRaw = data['memberIds'];
      final memberIds = (memberIdsRaw is List)
          ? memberIdsRaw.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toSet()
          : <String>{};

      // Idempotent: already has access
      if (memberIds.contains(authUid)) {
        return GlobalPublicLeagueJoinStatus.alreadyJoined;
      }

      // VIEWER JOIN: do not touch counts, do not create membership doc
      if (mode == LeagueJoinMode.viewer) {
        tx.set(
          leagueRef,
          <String, dynamic>{
            // RULES: append ONLY self (auth uid)
            'memberIds': FieldValue.arrayUnion([authUid]),
            'updatedAtMs': now,
          },
          SetOptions(merge: true),
        );
        return GlobalPublicLeagueJoinStatus.joined;
      }

      // PARTICIPANT JOIN
      final maxTeams = (data['maxTeams'] as num?)?.toInt() ?? league.league.maxTeams;
      final isFullStored = data['isFull'] == true || data['isFull'] == 1;

      // CRITICAL: derive registeredCount from remote doc (rules expect +1)
      final registeredCount = (data['registeredCount'] as num?)?.toInt() ?? 0;

      if (isFullStored || registeredCount >= maxTeams) {
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

      // If membership exists, treat as already joined but ensure access is granted
      final membershipSnap = await tx.get(membershipsRef);
      if (membershipSnap.exists) {
        tx.set(
          leagueRef,
          <String, dynamic>{
            'memberIds': FieldValue.arrayUnion([authUid]),
            'updatedAtMs': now,
          },
          SetOptions(merge: true),
        );
        return GlobalPublicLeagueJoinStatus.alreadyJoined;
      }

      final nextCount = registeredCount + 1;
      final nextIsFull = nextCount >= maxTeams;

      // Membership doc must use auth uid for both id and userId (rules-friendly)
      tx.set(
        membershipsRef,
        <String, dynamic>{
          'id': authUid,
          'leagueId': leagueId,
          'userId': authUid,
          'teamId': null,
          'role': LeagueRole.member.index,
          'updatedAtMs': now,
          'version': 1,
        },
        SetOptions(merge: true),
      );

      // League update must append ONLY auth uid
      tx.set(
        leagueRef,
        <String, dynamic>{
          'registeredCount': nextCount,
          'isFull': nextIsFull,
          'memberIds': FieldValue.arrayUnion([authUid]),
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

    // Best-effort local sync using existing join-by-code flow.
    // IMPORTANT: local identity should be Firebase UID so memberships line up.
    League? syncedLeague;
    try {
      syncedLeague = await _localRepo.joinLeagueLocallyByCode(
        joinCode: joinCode,
        userId: authUid,
        mode: mode,
        placeholderBuilder: (generatedLeagueId) {
          return league.league.copyWith(
            id: generatedLeagueId,
            updatedAtMs: wallNow,
          );
        },
      );
    } catch (_) {
      // non-fatal
    }

    return GlobalPublicLeagueJoinResult(
      status: status,
      league: syncedLeague ?? league.league,
    );
  }
}
