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
/// BUSINESS CRITICAL RULES:
/// - Participant capacity MUST NOT be exceeded.
/// - Viewers MUST NOT be counted as participants.
/// - Joining must be blocked completely if league is full.
/// - Participant counting is derived from participants collection (memberships).
///
/// IMPLEMENTATION NOTE (cloud_firestore Transaction API limitation):
/// - This SDK version Transaction.get() does not support collection/query reads.
/// - To keep joins atomic and safe under concurrency, we maintain a league-side
///   counter `participantsCount` that is incremented ONLY when a membership doc
///   is created (participant). Viewers never create memberships, so they never
///   affect `participantsCount`.
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

  String _requireAuthUid() {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) {
      throw StateError('Not signed in (FirebaseAuth.currentUser == null).');
    }
    return uid;
  }

  int _safeInt(dynamic v, {required int fallback}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  bool _safeBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v.toInt() == 1;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return false;
  }

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

    final authUid = _requireAuthUid();

    final leagueRef = _firestore.collection('leagues').doc(leagueId);

    // Deterministic membership doc id by auth uid
    final membershipRef = leagueRef.collection('memberships').doc(authUid);

    final wallNow = DateTime.now().millisecondsSinceEpoch;

    final GlobalPublicLeagueJoinStatus status = await _firestore.runTransaction((tx) async {
      final snap = await tx.get(leagueRef);
      final data = (snap.data() ?? <String, dynamic>{});

      // Ensure updatedAtMs strictly increases to satisfy rules that use ">"
      final prevUpdatedAtMs = _safeInt(data['updatedAtMs'], fallback: 0);
      final now = (wallNow > prevUpdatedAtMs) ? wallNow : (prevUpdatedAtMs + 1);

      final isPrivate = _safeBool(data['isPrivate']);
      if (isPrivate) return GlobalPublicLeagueJoinStatus.privateLeague;

      final isFinished = _safeBool(data['isFinished']);
      if (isFinished) return GlobalPublicLeagueJoinStatus.finished;

      final maxTeams = _safeInt(data['maxTeams'], fallback: league.league.maxTeams);
      final safeMaxTeams = (maxTeams > 0) ? maxTeams : league.league.maxTeams;

      // If membership exists, user is already a PARTICIPANT (idempotent).
      final membershipSnap = await tx.get(membershipRef);
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

      // Canonical participants count (atomic cache):
      // This field MUST only be incremented when a membership doc is created.
      final participantsCount = _safeInt(data['participantsCount'], fallback: _safeInt(data['registeredCount'], fallback: 0));

      // BLOCK ALL joins if full (participant + viewer).
      if (participantsCount >= safeMaxTeams) {
        tx.set(
          leagueRef,
          <String, dynamic>{
            'isFull': true,
            // defensive: keep cache aligned
            'participantsCount': participantsCount,
            'updatedAtMs': now,
          },
          SetOptions(merge: true),
        );
        return GlobalPublicLeagueJoinStatus.full;
      }

      // VIEWER JOIN:
      // - MUST NOT create membership
      // - MUST NOT change participantsCount
      if (mode == LeagueJoinMode.viewer) {
        tx.set(
          leagueRef,
          <String, dynamic>{
            'memberIds': FieldValue.arrayUnion([authUid]),
            'updatedAtMs': now,
          },
          SetOptions(merge: true),
        );
        return GlobalPublicLeagueJoinStatus.joined;
      }

      // PARTICIPANT JOIN:
      final nextCount = participantsCount + 1;

      // Overflow protection (hard stop).
      if (nextCount > safeMaxTeams) {
        tx.set(
          leagueRef,
          <String, dynamic>{
            'isFull': true,
            'participantsCount': participantsCount,
            'updatedAtMs': now,
          },
          SetOptions(merge: true),
        );
        return GlobalPublicLeagueJoinStatus.full;
      }

      tx.set(
        membershipRef,
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

      // League update:
      // - participantsCount increments ONLY here (participant join)
      // - viewers never touch it
      // - keep registeredCount in sync for older UI (best-effort)
      tx.set(
        leagueRef,
        <String, dynamic>{
          'participantsCount': nextCount,
          'registeredCount': nextCount,
          'isFull': nextCount >= safeMaxTeams,
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
