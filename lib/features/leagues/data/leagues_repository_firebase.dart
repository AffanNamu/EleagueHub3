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

  /// Validates master league ownership.
  /// Caches the result to avoid redundant reads.
  Future<Map<String, dynamic>> _requireMasterLeagueOwnerOrThrow({
    required String masterLeagueId,
    required String authUid,
  }) async {
    final id = masterLeagueId.trim();
    if (id.isEmpty) return <String, dynamic>{};

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

    if (ownerId.isNotEmpty && ownerId == authUid) return data;

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
    if (userRole == 'owner' || userRole == 'admin') return data;

    throw const UserFriendlyException(
      'Only the Master League owner can create competitions inside it.',
    );
  }

  /// Reads plan from already-fetched master league data, avoiding extra get().
  MasterLeaguePlan _planFromData(Map<String, dynamic> data) {
    return MasterLeaguePlan.fromString(data['plan'] as String?);
  }

  /// Fallback: reads plan from server if we don't have cached data.
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

  /// Returns candidate league IDs for a new competition inside a master league.
  /// Uses [mlData] if provided to avoid redundant server reads.
  Future<List<String>> _candidateCompetitionLeagueIdsForMasterLeague({
    required String masterLeagueId,
    Map<String, dynamic>? mlData,
  }) async {
    final masterId = masterLeagueId.trim();
    if (masterId.isEmpty) return <String>[_uuid.v4()];

    final plan = mlData != null
        ? _planFromData(mlData)
        : await _getMasterLeaguePlan(masterId);

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

  /// Builds complete write data for a league document.
  ///
  /// CRITICAL: All identity fields must match request.auth.uid
  /// for Firebase security rules to pass.
  Map<String, dynamic> _buildLeagueWriteData({
    required League fixed,
    required String authUid,
    required int now,
    required String requestedMasterLeagueId,
    required bool forCreate,
  }) {
    final leagueData = <String, dynamic>{
      ...fixed.toJson(),
      // These MUST match request.auth.uid — rules check all three
      'organizerUid': authUid,
      'ownerUid': authUid,
      'ownerId': authUid,
      // Also set organizerUserId to authUid so looksLikeFirebaseUid passes
      'organizerUserId': authUid,
      'isPrivate': fixed.isPrivate,
      'updatedAtMs': now,
    };

    // Ensure memberIds is always a list containing the auth user
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

    // Handle masterLeagueId field
    if (requestedMasterLeagueId.isEmpty) {
      if (!forCreate) {
        leagueData['masterLeagueId'] = FieldValue.delete();
      } else {
        leagueData.remove('masterLeagueId');
      }
    } else {
      leagueData['masterLeagueId'] = requestedMasterLeagueId;
    }

    // Remove null values — Firestore rules may reject them
    leagueData.removeWhere((key, value) => value == null);
    return leagueData;
  }

  /// Creates a league document at a specific ID.
  ///
  /// CRITICAL: Does NOT pre-read the league doc before writing.
  /// A get() on a non-existent doc triggers canReadLeague() which fails
  /// because the doc doesn't exist yet.
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
      organizerUserId: authUid,
      code: league.code.trim().toUpperCase(),
      updatedAtMs: now,
    );

    final leagueRef = _leaguesCol.doc(id);
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
      debugPrint(
        '[LeaguesRepoFirebase] Write data keys: ${writeData.keys.toList()}',
      );
      if (requestedMasterLeagueId.isNotEmpty) {
        debugPrint(
          '[LeaguesRepoFirebase] masterLeagueId in payload: '
          '${writeData['masterLeagueId']}',
        );
      }
    }

    // Write league document — NO pre-read get()
    await leagueRef
        .set(writeData, SetOptions(merge: false))
        .timeout(const Duration(seconds: 20));

    if (kDebugMode) {
      debugPrint(
        '[LeaguesRepoFirebase] League doc written successfully: $id',
      );
    }

    // Write membership using the self-create rule path:
    // signedIn() && request.auth.uid == membershipId && ...
    // This does NOT require canManageLeague which would try to read
    // the just-created league doc (might not be immediately readable).
    try {
      await membershipRef
          .set(membership.toRemoteMap(), SetOptions(merge: false))
          .timeout(const Duration(seconds: 15));

      if (kDebugMode) {
        debugPrint(
          '[LeaguesRepoFirebase] Membership written for league: $id',
        );
      }
    } catch (e) {
      // Membership write is non-fatal — league was created successfully.
      if (kDebugMode) {
        debugPrint(
          '[LeaguesRepoFirebase] Membership write failed (non-fatal): $e',
        );
      }
    }

    if (kDebugMode) {
      debugPrint('Competition created successfully inside Master League');
    }

    return id;
  }

  Future<String> _createMasterLeagueCompetitionWithReservedSlot({
    required League league,
    required String authUid,
    required String masterLeagueId,
    Map<String, dynamic>? mlData,
  }) async {
    final candidates = await _candidateCompetitionLeagueIdsForMasterLeague(
      masterLeagueId: masterLeagueId,
      mlData: mlData,
    );

    Object? lastError;

    for (final candidateId in candidates) {
      try {
        final result = await _createLeagueAtExactId(
          league: league,
          id: candidateId,
          authUid: authUid,
          requestedMasterLeagueId: masterLeagueId,
        );

        if (kDebugMode) {
          debugPrint(
            'Competition created successfully inside Master League '
            '(id=$result, masterLeague=$masterLeagueId)',
          );
        }

        return result;
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

    final plan = mlData != null
        ? _planFromData(mlData)
        : await _getMasterLeaguePlan(masterLeagueId);
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

  /// Save (create or update) a league.
  ///
  /// CRITICAL FIXES for master league competitions:
  /// 1. For NEW leagues with masterLeagueId and empty id: slot reservation path
  ///    (no pre-read get() that would fail on non-existent doc)
  /// 2. Master league data is fetched ONCE and reused (avoids redundant reads)
  /// 3. For other new leagues: direct set() without pre-read
  /// 4. organizerUserId is set to authUid for rules compatibility
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

      // Validate master league ownership and cache the data
      Map<String, dynamic>? mlData;
      if (requestedMasterLeagueId.isNotEmpty) {
        mlData = await _requireMasterLeagueOwnerOrThrow(
          masterLeagueId: requestedMasterLeagueId,
          authUid: authUid,
        );
      }

      // CASE 1: New competition inside a master league (empty id)
      // Use slot reservation path — no pre-read get()
      if (requestedMasterLeagueId.isNotEmpty && league.id.trim().isEmpty) {
        return await _createMasterLeagueCompetitionWithReservedSlot(
          league: league,
          authUid: authUid,
          masterLeagueId: requestedMasterLeagueId,
          mlData: mlData,
        );
      }

      final id = league.id.trim().isEmpty ? _uuid.v4() : league.id.trim();
      final leagueRef = _leaguesCol.doc(id);

      final now = DateTime.now().millisecondsSinceEpoch;
      final fixed = league.copyWith(
        id: id,
        organizerUid: authUid,
        organizerUserId: authUid,
        code: league.code.trim().toUpperCase(),
        updatedAtMs: now,
      );

      final membershipRef = leagueRef.collection('memberships').doc(authUid);
      final membership = _organizerMembership(
        leagueId: id,
        authUid: authUid,
        now: now,
      );

      // Try to read existing doc — but handle permission-denied gracefully
      // for non-existent docs (canReadLeague requires doc to exist).
      bool docExists = false;
      Map<String, dynamic>? existingData;

      try {
        final existing = await leagueRef
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 15));
        docExists = existing.exists;
        if (docExists) {
          existingData = existing.data();
        }
      } catch (e) {
        // Permission-denied on get() means the doc doesn't exist
        // (canReadLeague checks doc existence). Proceed with create.
        if (e is FirebaseException && e.code == 'permission-denied') {
          if (kDebugMode) {
            debugPrint(
              '[LeaguesRepoFirebase] get() permission-denied for $id — '
              'treating as new doc',
            );
          }
          docExists = false;
          existingData = null;
        } else {
          rethrow;
        }
      }

      if (docExists && existingData != null) {
        // UPDATING existing league
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
          if (existingMasterLeagueId.isNotEmpty &&
              existingMasterLeagueId != requestedMasterLeagueId) {
            throw const UserFriendlyException(
              "We couldn't move this competition. Please refresh and try again.",
            );
          }
        }

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
      } else {
        // CREATING new league — use direct set() without pre-read
        return await _createLeagueAtExactId(
          league: league,
          id: id,
          authUid: authUid,
          requestedMasterLeagueId: requestedMasterLeagueId,
        );
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
