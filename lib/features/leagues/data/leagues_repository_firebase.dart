import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../master_leagues/domain/master_league_plan.dart';
import '../models/league.dart';
import '../models/membership.dart';

class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

class _CompetitionSlotTakenException implements Exception {
  const _CompetitionSlotTakenException();
}

class LeaguesRepositoryFirebase {
  LeaguesRepositoryFirebase({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Uuid _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> get _leaguesCol =>
      _firestore.collection('leagues');

  CollectionReference<Map<String, dynamic>> get _masterLeaguesCol =>
      _firestore.collection('master_leagues');

  String _requireAuthUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const UserFriendlyException('Please sign in and try again.');
    }
    return uid;
  }

  Never _rethrowFriendly(Object error) {
    if (error is UserFriendlyException) throw error;

    if (error is SocketException) {
      throw const UserFriendlyException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    }
    if (error is TimeoutException) {
      throw const UserFriendlyException(
        'Your internet connection seems unstable. Please try again.',
      );
    }

    if (error is FirebaseException) {
      if (kDebugMode) {
        debugPrint(
          '[LeaguesRepoFirebase] FirebaseException code=${error.code} '
          'message=${error.message}',
        );
      }
      switch (error.code) {
        case 'unavailable':
        case 'deadline-exceeded':
          throw const UserFriendlyException(
            'Your network appears to be offline. Please check your connection and try again.',
          );
        case 'permission-denied':
          throw const UserFriendlyException(
            'You don\'t have permission to do this. Please check your access and try again.',
          );
        case 'unauthenticated':
          throw const UserFriendlyException(
            'Please sign in and try again.',
          );
        default:
          throw const UserFriendlyException(
            "We couldn't complete this action. Please try again.",
          );
      }
    }

    throw const UserFriendlyException('Something went wrong. Please try again.');
  }

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

  Future<void> _requireMasterLeagueOwnerOrThrow({
    required String masterLeagueId,
    required String authUid,
  }) async {
    final id = masterLeagueId.trim();
    if (id.isEmpty) return;

    final snap = await _masterLeaguesCol
        .doc(id)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));

    if (!snap.exists) {
      throw const UserFriendlyException(
        "We couldn't find that Master League. Please refresh and try again.",
      );
    }

    final data = snap.data() ?? <String, dynamic>{};
    final ownerId =
        (data['ownerId'] as String? ?? data['ownerUid'] as String? ?? '')
            .trim();

    if (ownerId.isNotEmpty && ownerId == authUid) return;

    final roles = <String, String>{};
    final rawRoles = data['roles'];
    if (rawRoles is Map) {
      for (final entry in rawRoles.entries) {
        final k = entry.key.toString().trim();
        final v = (entry.value ?? '').toString().trim().toLowerCase();
        if (k.isNotEmpty && v.isNotEmpty) roles[k] = v;
      }
    }

    final userRole = roles[authUid] ?? '';
    if (userRole == 'owner' || userRole == 'admin') return;

    final memberIds = <String>{};
    final rawMembers = data['memberIds'];
    if (rawMembers is List) {
      for (final v in rawMembers) {
        final s = (v ?? '').toString().trim();
        if (s.isNotEmpty) memberIds.add(s);
      }
    }

    if (memberIds.contains(authUid) && roles.containsKey(authUid)) return;

    throw const UserFriendlyException(
      'Only the Master League owner can create competitions inside it.',
    );
  }

  Future<MasterLeaguePlan> _getMasterLeaguePlan(String masterLeagueId) async {
    final id = masterLeagueId.trim();
    if (id.isEmpty) return MasterLeaguePlan.basic;

    final snap = await _masterLeaguesCol
        .doc(id)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));

    if (!snap.exists) {
      throw const UserFriendlyException(
        "We couldn't find that Master League. Please refresh and try again.",
      );
    }

    final data = snap.data() ?? <String, dynamic>{};
    return MasterLeaguePlan.fromString(data['plan'] as String?);
  }

  String _competitionLimitMessage(MasterLeaguePlan plan) {
    return 'You have reached the limit of ${plan.maxLeagues} competitions '
        'for your ${plan.displayName} plan.';
  }

  Future<List<String>> _candidateCompetitionLeagueIdsForMasterLeague({
    required String masterLeagueId,
  }) async {
    final masterId = masterLeagueId.trim();
    if (masterId.isEmpty) return <String>[_uuid.v4()];

    final plan = await _getMasterLeaguePlan(masterId);

    if (plan == MasterLeaguePlan.elite) {
      return <String>[_uuid.v4()];
    }

    final max = plan.maxLeagues;
    final prefix = 'mlc_${masterId}_';

    final snap = await _firestore
        .collection('leagues')
        .where('masterLeagueId', isEqualTo: masterId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));

    final ids = snap.docs
        .map((d) => d.id.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);

    final takenSlots = <int>{};
    int legacyCount = 0;

    for (final id in ids) {
      if (!id.startsWith(prefix)) {
        legacyCount += 1;
        continue;
      }
      final tail = id.substring(prefix.length).trim();
      final slot = int.tryParse(tail);
      if (slot != null && slot >= 1 && slot <= max) {
        takenSlots.add(slot);
      } else {
        legacyCount += 1;
      }
    }

    final reserved = legacyCount.clamp(0, max);
    for (int i = 1; i <= reserved; i++) {
      takenSlots.add(i);
    }

    if (ids.length >= max) {
      throw UserFriendlyException(_competitionLimitMessage(plan));
    }

    final candidates = <String>[];
    for (int slot = 1; slot <= max; slot++) {
      if (!takenSlots.contains(slot)) {
        candidates.add('${prefix}$slot');
      }
    }

    if (candidates.isEmpty) {
      throw UserFriendlyException(_competitionLimitMessage(plan));
    }

    return candidates;
  }

  Membership _organizerMembership({
    required String leagueId,
    required String authUid,
    required int now,
  }) {
    return Membership(
      id: authUid,
      leagueId: leagueId,
      userId: authUid,
      teamId: null,
      role: LeagueRole.organizer,
      updatedAtMs: now,
      version: 1,
    );
  }

  Map<String, dynamic> _buildLeagueWriteData({
    required League fixed,
    required String authUid,
    required int now,
    required String requestedMasterLeagueId,
    required bool forCreate,
  }) {
    final leagueData = <String, dynamic>{
      ...fixed.toJson(),
      'organizerUid': authUid,
      'ownerUid': authUid,
      'ownerId': authUid,
      'isPrivate': fixed.isPrivate,
      'updatedAtMs': now,
    };

    final rawMemberIds = leagueData['memberIds'];
    final memberIds = <String>{authUid};
    if (rawMemberIds is List) {
      for (final value in rawMemberIds) {
        final v = value is String ? value.trim() : '';
        if (v.isNotEmpty) {
          memberIds.add(v);
        }
      }
    }
    leagueData['memberIds'] = memberIds.toList(growable: false);

    if (requestedMasterLeagueId.isEmpty) {
      if (!forCreate) {
        leagueData['masterLeagueId'] = FieldValue.delete();
      } else {
        leagueData.remove('masterLeagueId');
      }
    } else {
      leagueData['masterLeagueId'] = requestedMasterLeagueId;
    }

    leagueData.removeWhere((key, value) => value == null);
    return leagueData;
  }

  Future<String> _createLeagueAtExactId({
    required League league,
    required String id,
    required String authUid,
    required String requestedMasterLeagueId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final fixed = league.copyWith(
      id: id,
      organizerUid: authUid,
      code: league.code.trim().toUpperCase(),
      updatedAtMs: now,
    );

    final leagueRef = _leaguesCol.doc(id);
    
    // Explicitly check for overwrite to prevent slot issues natively
    final docSnap = await leagueRef.get();
    if (docSnap.exists) {
      throw const _CompetitionSlotTakenException();
    }

    final membershipRef = leagueRef.collection('memberships').doc(authUid);
    final membership = _organizerMembership(
      leagueId: id,
      authUid: authUid,
      now: now,
    );

    final writeData = _buildLeagueWriteData(
      fixed: fixed,
      authUid: authUid,
      now: now,
      requestedMasterLeagueId: requestedMasterLeagueId,
      forCreate: true,
    );

    if (kDebugMode) {
      debugPrint(
        '[LeaguesRepoFirebase] Creating league id=$id '
        'masterLeague=$requestedMasterLeagueId '
        'authUid=$authUid',
      );
    }

    await leagueRef
        .set(writeData, SetOptions(merge: false))
        .timeout(const Duration(seconds: 20));

    try {
      await membershipRef
          .set(membership.toRemoteMap(), SetOptions(merge: false))
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[LeaguesRepoFirebase] Membership write failed (non-fatal): $e',
        );
      }
    }

    return id;
  }

  Future<String> _createMasterLeagueCompetitionWithReservedSlot({
    required League league,
    required String authUid,
    required String masterLeagueId,
  }) async {
    final candidates = await _candidateCompetitionLeagueIdsForMasterLeague(
      masterLeagueId: masterLeagueId,
    );

    Object? lastError;

    for (final candidateId in candidates) {
      try {
        return await _createLeagueAtExactId(
          league: league,
          id: candidateId,
          authUid: authUid,
          requestedMasterLeagueId: masterLeagueId,
        );
      } on _CompetitionSlotTakenException {
        lastError = const _CompetitionSlotTakenException();
        continue;
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            '[LeaguesRepoFirebase] Error creating at $candidateId: $e',
          );
        }
        lastError = e;
        if (e is FirebaseException &&
            (e.code == 'permission-denied' || e.code == 'already-exists')) {
          continue;
        }
        break;
      }
    }

    if (lastError is Object && lastError is! _CompetitionSlotTakenException) {
      _rethrowFriendly(lastError);
    }

    final plan = await _getMasterLeaguePlan(masterLeagueId);
    throw UserFriendlyException(_competitionLimitMessage(plan));
  }

  Future<List<League>> getAllLeagues() async {
    try {
      final uid = _requireAuthUid();

      final snapshot = await _leaguesCol
          .where('memberIds', arrayContains: uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      return snapshot.docs.map(_docToLeague).toList(growable: false);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Stream<List<League>> watchLeagues() {
    try {
      final uid = _requireAuthUid();

      final base = _leaguesCol
          .where('memberIds', arrayContains: uid)
          .snapshots(includeMetadataChanges: true);

      final serverOnly = base.where((snap) => !snap.metadata.isFromCache).map(
            (snapshot) =>
                snapshot.docs.map(_docToLeague).toList(growable: false),
          );

      return serverOnly.handleError((error, stack) {
        if (kDebugMode) {
          debugPrint('LeaguesRepositoryFirebase.watchLeagues error: $error');
        }
      });
    } catch (_) {
      return const Stream<List<League>>.empty();
    }
  }

  Future<League?> getLeagueById(String id) async {
    try {
      _requireAuthUid();

      final doc = await _leaguesCol
          .doc(id)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      if (!doc.exists) return null;
      return _snapToLeague(doc);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<String> saveLeague(League league) async {
    try {
      final authUid = _requireAuthUid();
      final requestedMasterLeagueId = league.masterLeagueId.trim();

      if (kDebugMode) {
        debugPrint(
          '[LeaguesRepoFirebase] saveLeague: id="${league.id}" '
          'masterLeagueId="$requestedMasterLeagueId"',
        );
      }

      if (requestedMasterLeagueId.isNotEmpty) {
        await _requireMasterLeagueOwnerOrThrow(
          masterLeagueId: requestedMasterLeagueId,
          authUid: authUid,
        );
      }

      if (requestedMasterLeagueId.isNotEmpty && league.id.trim().isEmpty) {
        return await _createMasterLeagueCompetitionWithReservedSlot(
          league: league,
          authUid: authUid,
          masterLeagueId: requestedMasterLeagueId,
        );
      }

      final id = league.id.trim().isEmpty ? _uuid.v4() : league.id.trim();
      final leagueRef = _leaguesCol.doc(id);

      final now = DateTime.now().millisecondsSinceEpoch;
      final fixed = league.copyWith(
        id: id,
        organizerUid: authUid,
        code: league.code.trim().toUpperCase(),
        updatedAtMs: now,
      );

      final membershipRef = leagueRef.collection('memberships').doc(authUid);
      final membership = _organizerMembership(
        leagueId: id,
        authUid: authUid,
        now: now,
      );

      final existing = await leagueRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      if (existing.exists) {
        final existingData = existing.data() ?? <String, dynamic>{};
        final existingOwner =
            (existingData['ownerUid'] as String? ??
                    existingData['organizerUid'] as String? ??
                    existingData['ownerId'] as String? ??
                    '')
                .trim();

        if (existingOwner.isNotEmpty && existingOwner != authUid) {
          throw const UserFriendlyException(
            'You don\'t have permission to edit this league.',
          );
        }

        if (requestedMasterLeagueId.isNotEmpty) {
          final existingMasterLeagueId =
              (existingData['masterLeagueId'] as String? ?? '').trim();
          if (existingMasterLeagueId != requestedMasterLeagueId) {
            throw const UserFriendlyException(
              "We couldn't move this competition. Please refresh and try again.",
            );
          }
        }
      }

      if (!existing.exists) {
        final writeData = _buildLeagueWriteData(
          fixed: fixed,
          authUid: authUid,
          now: now,
          requestedMasterLeagueId: requestedMasterLeagueId,
          forCreate: true,
        );

        await leagueRef
            .set(writeData, SetOptions(merge: false))
            .timeout(const Duration(seconds: 20));

        try {
          await membershipRef
              .set(membership.toRemoteMap(), SetOptions(merge: false))
              .timeout(const Duration(seconds: 15));
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '[LeaguesRepoFirebase] Membership write failed (non-fatal): $e',
            );
          }
        }
      } else {
        final batch = _firestore.batch();
        batch.set(
          leagueRef,
          _buildLeagueWriteData(
            fixed: fixed,
            authUid: authUid,
            now: now,
            requestedMasterLeagueId: requestedMasterLeagueId,
            forCreate: false,
          ),
          SetOptions(merge: true),
        );

        batch.set(
          membershipRef,
          membership.toRemoteMap(),
          SetOptions(merge: true),
        );

        await batch.commit().timeout(const Duration(seconds: 25));
      }

      return id;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LeaguesRepoFirebase] saveLeague error: $e');
      }
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> deleteLeague(String leagueId) async {
    try {
      _requireAuthUid();
      await _leaguesCol
          .doc(leagueId)
          .delete()
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }
}
