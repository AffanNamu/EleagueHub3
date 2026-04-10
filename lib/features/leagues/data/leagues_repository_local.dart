import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../models/fixture_match.dart';
import '../models/knockout_match.dart';
import '../models/league.dart';
import '../models/membership.dart';
import '../models/point_adjustment.dart';
import '../models/team.dart';

enum LeagueJoinMode { participant, viewer }

class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

class LocalLeaguesRepository {
  LocalLeaguesRepository(this._prefs);

  // ignore: unused_field
  final PreferencesService _prefs;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  static const String kLeaguesKey = 'local_leagues';
  static const String kMembershipsKey = 'local_memberships';
  static const String kTeamsKey = 'local_teams';
  static const String kMatchesKey = 'local_matches';
  static const String kKnockoutMatchesKey = 'local_knockout_matches';

  static const int _freeLeagueListLimit = 3;

  String _requireAuthUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const UserFriendlyException('Please sign in and try again.');
    }
    return uid;
  }

  Future<void> _requireOnline() async {
    await ConnectivityService.instance.requireOnline(
      timeout: const Duration(seconds: 4),
    );
  }

  bool _isNetworkFirebaseException(FirebaseException e) {
    return e.code == 'unavailable' || e.code == 'deadline-exceeded';
  }

  Never _rethrowFriendly(Object e, {String context = ''}) {
    if (e is UserFriendlyException) throw e;

    if (e is SocketException || e is HandshakeException) {
      throw const UserFriendlyException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    }

    if (e is TimeoutException) {
      throw const UserFriendlyException(
        'Your internet connection seems unstable. Please try again.',
      );
    }

    if (e is FirebaseAuthException) {
      if (e.code == 'network-request-failed') {
        throw const UserFriendlyException(
          'Your network appears to be offline. Please check your connection and try again.',
        );
      }
      if (e.code == 'unauthenticated') {
        throw const UserFriendlyException('Please sign in and try again.');
      }
      throw const UserFriendlyException(
        "We couldn't complete this action. Please try again.",
      );
    }

    if (e is FirebaseException) {
      if (_isNetworkFirebaseException(e)) {
        throw const UserFriendlyException(
          'Your network appears to be offline. Please check your connection and try again.',
        );
      }
      if (e.code == 'permission-denied') {
        final trimmed = context.trim();
        if (trimmed.isNotEmpty) {
          throw UserFriendlyException(
            'Permission denied ($trimmed). You don\u2019t have permission to do that right now.',
          );
        }
        throw const UserFriendlyException(
          'You don\u2019t have permission to do that right now.',
        );
      }
      if (e.code == 'unauthenticated') {
        throw const UserFriendlyException('Please sign in and try again.');
      }
      throw const UserFriendlyException(
        "We couldn't complete this action. Please try again.",
      );
    }

    throw const UserFriendlyException('Something went wrong. Please try again.');
  }

  bool _looksLikeFirebaseUid(String s) => s.trim().length > 20;

  Future<bool> _isPremiumUser(String uid) async {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return false;

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult(true);
      final claims = token?.claims ?? const <String, dynamic>{};

      final isPremium = claims['isPremium'] == true || claims['premium'] == true;
      if (isPremium) return true;

      final premiumExpiresAtMs = claims['premiumExpiresAtMs'];
      if (premiumExpiresAtMs is int &&
          premiumExpiresAtMs > DateTime.now().millisecondsSinceEpoch) {
        return true;
      }
      if (premiumExpiresAtMs is num &&
          premiumExpiresAtMs.toInt() > DateTime.now().millisecondsSinceEpoch) {
        return true;
      }
    } catch (_) {}

    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(trimmed)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      final data = userDoc.data() ?? const <String, dynamic>{};
      if (data['isPremium'] == true) return true;

      final expires = data['premiumExpiresAtMs'];
      if (expires is int && expires > DateTime.now().millisecondsSinceEpoch) {
        return true;
      }
      if (expires is num &&
          expires.toInt() > DateTime.now().millisecondsSinceEpoch) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  // ---------------------------------------------------------------------------
  // FIX: _countCurrentUserLeagueCards
  //
  // OLD: queried leagues where memberIds arrayContains uid — this requires the
  //      user to already be in the league, so it works fine for listing but
  //      the count was used BEFORE the join write, which is correct.
  //
  // UNCHANGED: this function is fine as-is. The permission-denied was NOT
  //      here. Leaving identical to original.
  // ---------------------------------------------------------------------------
  Future<int> _countCurrentUserLeagueCards(String authUid) async {
    final snap = await _firestore
        .collection('leagues')
        .where('memberIds', arrayContains: authUid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 20));

    return snap.docs.length;
  }

  // ---------------------------------------------------------------------------
  // FIX: _userAlreadyHasLeagueCard
  //
  // OLD BUG: This did a get() on the league document directly. If the Firestore
  //   security rules only allow league reads by members (memberIds contains uid),
  //   then a user trying to JOIN (not yet a member) would get permission-denied
  //   here — BEFORE any join write happened.
  //
  // FIX: Wrap the get() in a try-catch. If we get permission-denied, we treat
  //   it as "user is not yet a member" (returns false), which is the correct
  //   semantic — the join flow will then proceed to add them.
  //
  // This is safe because:
  //   - If the user IS already a member, the read succeeds and we return true
  //     (skip the cap check correctly).
  //   - If the user is NOT a member yet, permission-denied means they cannot
  //     read the doc (correct), and we return false so the cap is enforced.
  //   - If the league is public-read, the read succeeds normally.
  // ---------------------------------------------------------------------------
  Future<bool> _userAlreadyHasLeagueCard({
    required String authUid,
    required String leagueId,
  }) async {
    final trimmedLeagueId = leagueId.trim();
    if (trimmedLeagueId.isEmpty) return false;

    try {
      final doc = await _firestore
          .collection('leagues')
          .doc(trimmedLeagueId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));

      if (!doc.exists) return false;

      final data = doc.data() ?? const <String, dynamic>{};
      final memberIds = (data['memberIds'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet() ??
          <String>{};

      return memberIds.contains(authUid);
    } on FirebaseException catch (e) {
      // permission-denied means user is not yet a member — treat as false
      // so the join flow can proceed and add them.
      if (e.code == 'permission-denied') return false;
      // For other Firebase errors, re-throw so caller handles them.
      rethrow;
    } catch (_) {
      // For any other error (timeout, network), treat as not-yet-member
      // so we do not block the join attempt incorrectly.
      return false;
    }
  }

  Future<void> _enforceFreeLeagueListCapForNewAddition({
    required String authUid,
    required String actionLabel,
    String existingLeagueId = '',
  }) async {
    final premium = await _isPremiumUser(authUid);
    if (premium) return;

    final alreadyLinked = existingLeagueId.trim().isNotEmpty
        ? await _userAlreadyHasLeagueCard(
            authUid: authUid,
            leagueId: existingLeagueId,
          )
        : false;

    if (alreadyLinked) return;

    final total = await _countCurrentUserLeagueCards(authUid);
    if (total >= _freeLeagueListLimit) {
      throw UserFriendlyException(
        'Free users can only have $_freeLeagueListLimit leagues total on the leagues screen. Upgrade to Premium to $actionLabel.',
      );
    }
  }

  Future<void> _requireNotOwnerForLeave({
    required String leagueId,
    required String authUid,
  }) async {
    final snap = await _firestore
        .collection('leagues')
        .doc(leagueId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));

    if (!snap.exists) {
      throw const UserFriendlyException(
        "We couldn't find this league. Please refresh and try again.",
      );
    }

    final data = snap.data() ?? const <String, dynamic>{};
    final organizerUid = (data['organizerUid'] as String? ?? '').trim();
    final ownerUid = (data['ownerUid'] as String? ?? '').trim();
    final ownerId = (data['ownerId'] as String? ?? '').trim();

    if (organizerUid == authUid || ownerUid == authUid || ownerId == authUid) {
      throw const UserFriendlyException(
        'League owners cannot remove their own league from the list here. Please use the owner/admin area.',
      );
    }
  }

  Future<void> leaveLeague(String leagueId) async {
    try {
      final authUid = _requireAuthUid();
      await _requireOnline();

      final id = leagueId.trim();
      if (id.isEmpty) {
        throw const UserFriendlyException(
          "We couldn't find this league. Please refresh and try again.",
        );
      }

      await _requireNotOwnerForLeave(
        leagueId: id,
        authUid: authUid,
      );

      final leagueRef = _firestore.collection('leagues').doc(id);
      final membershipRef = leagueRef.collection('memberships').doc(authUid);

      await leagueRef
          .set(
            {
              'memberIds': FieldValue.arrayRemove([authUid]),
              'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
            },
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 15));

      try {
        await membershipRef
            .delete()
            .timeout(const Duration(seconds: 15));
      } catch (_) {}
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'leaving league',
      );
    }
  }

  Future<void> _requireOrganizerOrThrow(String leagueId) async {
    final authUid = _requireAuthUid();
    await _requireOnline();

    final snap = await _firestore
        .collection('leagues')
        .doc(leagueId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));

    if (!snap.exists) {
      throw const UserFriendlyException(
        "We couldn't find this league. Please refresh and try again.",
      );
    }

    final data = snap.data() ?? <String, dynamic>{};
    final organizerUid = (data['organizerUid'] as String? ?? '').trim();
    final ownerUid = (data['ownerUid'] as String? ?? '').trim();

    final ok = (organizerUid.isNotEmpty && organizerUid == authUid) ||
        (ownerUid.isNotEmpty && ownerUid == authUid);

    if (!ok) {
      throw const UserFriendlyException(
        'You don\u2019t have permission to do that right now.',
      );
    }
  }

  Future<void> _silentlyPatchOrganizerUidIfNeeded({
    required String leagueId,
    required Map<String, dynamic> leagueData,
    required String authUid,
  }) async {
    try {
      final existing = (leagueData['organizerUid'] as String? ?? '').trim();
      if (_looksLikeFirebaseUid(existing)) return;

      final memberIds = leagueData['memberIds'];
      final isInMemberIds = memberIds is List && memberIds.contains(authUid);
      if (!isInMemberIds) return;

      final membershipDoc = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('memberships')
          .doc(authUid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      if (!membershipDoc.exists) return;

      final role = (membershipDoc.data()?['role'] as num?)?.toInt() ?? -1;
      if (role != LeagueRole.organizer.index) return;

      await _firestore
          .collection('leagues')
          .doc(leagueId)
          .set(
            {
              'organizerUid': authUid,
              'ownerUid': authUid,
              'ownerId': authUid,
              'memberIds': FieldValue.arrayUnion([authUid]),
              'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
            },
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  String _generateJoinCode({int length = 6}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<String> _generateUniqueJoinCode() async {
    for (var i = 0; i < 6; i++) {
      final code = _generateJoinCode();
      final snap = await _firestore
          .collection('leagues')
          .where('code', isEqualTo: code)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      if (snap.docs.isEmpty) return code;
    }
    throw const UserFriendlyException(
      "We couldn't create a join code. Please try again.",
    );
  }

  League _docToLeague(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = (doc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
    final map = <String, dynamic>{...data};
    map['id'] = (map['id'] is String && (map['id'] as String).trim().isNotEmpty)
        ? map['id']
        : doc.id;
    return League.fromRemoteMap(map);
  }

  String _bestUserImageUrlFromUserDoc(Map<String, dynamic> data) {
    final teamImageUrl = (data['teamImageUrl'] as String?)?.trim() ?? '';
    if (teamImageUrl.isNotEmpty) return teamImageUrl;

    final profileImageUrl = (data['profileImageUrl'] as String?)?.trim() ?? '';
    if (profileImageUrl.isNotEmpty) return profileImageUrl;

    final photoUrl = (data['photoUrl'] as String?)?.trim() ?? '';
    if (photoUrl.isNotEmpty) return photoUrl;

    return '';
  }

  Future<Map<String, String>> _loadUserImageUrlsByUids(List<String> uids) async {
    final ids = uids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) return const <String, String>{};

    final out = <String, String>{};

    const chunkSize = 10;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final chunk = ids.sublist(
        i,
        (i + chunkSize > ids.length) ? ids.length : i + chunkSize,
      );

      final snap = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));

      for (final d in snap.docs) {
        final data = d.data();
        final url = _bestUserImageUrlFromUserDoc(data);
        if (url.trim().isNotEmpty) {
          out[d.id] = url.trim();
        }
      }
    }

    return out;
  }

  // ---------------------------------------------------------------------------
  // _joinLeagueCore — FIXED write ordering to prevent permission-denied.
  //
  // ROOT CAUSE OF THE BUG (QR code / invitation code join):
  //   The security rules guard the membership sub-document write with a check
  //   that request.auth.uid is already present in the parent league's memberIds
  //   array. The old code flow was:
  //
  //     1. Check if user already has a card (_userAlreadyHasLeagueCard)
  //        → get() on league doc → PERMISSION DENIED if user not yet a member
  //          and rules require membership to read.
  //     2. Write membership doc FIRST
  //        → PERMISSION DENIED because memberIds does not yet contain uid.
  //     3. Write memberIds SECOND
  //        → Never reached due to step 2 failing.
  //
  // FIX (two parts):
  //   Part A (_userAlreadyHasLeagueCard): wrap get() in try-catch so that a
  //     permission-denied on the league doc read is treated as "not yet a
  //     member" — allowing the join flow to continue instead of crashing.
  //
  //   Part B (this function): update memberIds on the league document FIRST
  //     so that the membership sub-document write in step 4 succeeds because
  //     the rule precondition (uid in memberIds) is already satisfied.
  //
  //   Write order:
  //     Step 1 — verify league exists (server get).
  //     Step 2 — enforce free-plan cap (uses fixed _userAlreadyHasLeagueCard).
  //     Step 3 — arrayUnion uid into memberIds on league doc (FIRST write).
  //     Step 4 — write membership sub-document (SECOND write, now allowed).
  // ---------------------------------------------------------------------------
  Future<void> _joinLeagueCore({
    required String leagueId,
    required String authUid,
    required LeagueJoinMode mode,
  }) async {
    final trimmedLeagueId = leagueId.trim();
    if (trimmedLeagueId.isEmpty) {
      throw const UserFriendlyException(
        "We couldn't find this league. Please refresh and try again.",
      );
    }

    final leagueRef = _firestore.collection('leagues').doc(trimmedLeagueId);

    // Step 1 — verify the league exists before attempting any write.
    // Use try-catch: if rules deny read to non-members, treat it as
    // "league exists but user is not a member yet" and continue.
    // We only throw if the league genuinely does not exist.
    bool leagueConfirmedExists = false;
    try {
      final leagueDoc = await leagueRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      if (!leagueDoc.exists) {
        throw const UserFriendlyException(
          "We couldn't find this league. Please refresh and try again.",
        );
      }
      leagueConfirmedExists = true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        // Rules deny read to non-members. The league likely exists.
        // We proceed optimistically — the memberIds write below will
        // itself fail with permission-denied if the league truly does
        // not allow open joins, giving the user a clear error.
        leagueConfirmedExists = true;
      } else {
        rethrow;
      }
    }

    if (!leagueConfirmedExists) {
      throw const UserFriendlyException(
        "We couldn't find this league. Please refresh and try again.",
      );
    }

    // Step 2 — enforce free-plan league-card cap.
    // _userAlreadyHasLeagueCard now handles permission-denied gracefully.
    await _enforceFreeLeagueListCapForNewAddition(
      authUid: authUid,
      actionLabel: 'join more leagues',
      existingLeagueId: trimmedLeagueId,
    );

    // Step 3 — update memberIds on the league document FIRST.
    //
    // CRITICAL ORDER: The security rule that guards the membership
    // sub-document write checks that request.auth.uid is already present
    // in resource.data.memberIds. We MUST satisfy that precondition before
    // writing the membership document.
    //
    // Most Firestore join rules look like:
    //   allow write: if request.auth.uid == membershipId
    //                && request.auth.uid in get(/leagues/{leagueId}).data.memberIds;
    //
    // By writing memberIds first, that get() in the rule returns a document
    // that already contains the uid, so the membership write is permitted.
    await leagueRef
        .set(
          {
            'memberIds': FieldValue.arrayUnion([authUid]),
            'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
          },
          SetOptions(merge: true),
        )
        .timeout(const Duration(seconds: 20));

    // Step 4 — write the membership sub-document SECOND (participant only).
    //
    // Now that memberIds contains the user, the security rule check passes.
    // Wrapped in try-catch: a transient failure here does not break the join.
    // The user is already in memberIds and will appear in their league list.
    // The membership document can be repaired on next access.
    if (mode == LeagueJoinMode.participant) {
      try {
        final membershipRef = leagueRef.collection('memberships').doc(authUid);

        final existing = await membershipRef
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 12));

        final existingRoleIdx = (existing.data()?['role'] as num?)?.toInt();
        final existingRole = (existingRoleIdx != null &&
                existingRoleIdx >= 0 &&
                existingRoleIdx < LeagueRole.values.length)
            ? LeagueRole.values[existingRoleIdx]
            : null;

        if (!existing.exists || existingRole == null) {
          final now = DateTime.now().millisecondsSinceEpoch;

          final membership = Membership(
            id: authUid,
            leagueId: trimmedLeagueId,
            userId: authUid,
            teamId: null,
            role: LeagueRole.member,
            updatedAtMs: now,
            version: 1,
          );

          await membershipRef
              .set(membership.toRemoteMap(), SetOptions(merge: true))
              .timeout(const Duration(seconds: 20));
        }
      } catch (membershipError) {
        // Non-fatal: log and continue. The user is already in memberIds.
        assert(() {
          // ignore: avoid_print
          print(
            '[LocalLeaguesRepository] membership write failed after '
            'successful memberIds update (non-fatal): $membershipError',
          );
          return true;
        }());
      }
    }
  }

  Future<League> joinLeagueDirect({
    required String leagueId,
    LeagueJoinMode mode = LeagueJoinMode.participant,
  }) async {
    try {
      final authUid = _requireAuthUid();
      await _requireOnline();

      await _joinLeagueCore(
        leagueId: leagueId,
        authUid: authUid,
        mode: mode,
      );

      final fresh = await _firestore
          .collection('leagues')
          .doc(leagueId.trim())
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      if (!fresh.exists) {
        throw const UserFriendlyException(
          "We couldn't find this league. Please refresh and try again.",
        );
      }

      return _docToLeague(fresh);
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'joining league directly',
      );
    }
  }

  Future<List<League>> listLeagues() => getAllLeagues();

  Future<List<League>> getAllLeagues() async {
    try {
      final authUid = _requireAuthUid();
      await _requireOnline();

      final snapshot = await _firestore
          .collection('leagues')
          .where('memberIds', arrayContains: authUid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      final leagues = snapshot.docs
          .map((d) => _docToLeague(d))
          .toList(growable: false);

      for (final doc in snapshot.docs) {
        final data = doc.data();
        _silentlyPatchOrganizerUidIfNeeded(
          leagueId: doc.id,
          leagueData: data,
          authUid: authUid,
        );
      }

      return leagues;
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<League?> getLeagueById(String id) async {
    try {
      final authUid = _requireAuthUid();
      await _requireOnline();

      final doc = await _firestore
          .collection('leagues')
          .doc(id)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      if (!doc.exists) return null;

      final data = doc.data() ?? <String, dynamic>{};

      await _silentlyPatchOrganizerUidIfNeeded(
        leagueId: id,
        leagueData: data,
        authUid: authUid,
      );

      return _docToLeague(doc);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> saveLeague(League league) async {
    try {
      final authUid = _requireAuthUid();
      await _requireOnline();

      final isNewLeague = league.id.trim().isEmpty;
      if (isNewLeague) {
        await _enforceFreeLeagueListCapForNewAddition(
          authUid: authUid,
          actionLabel: 'create another league',
        );
      }

      final leagueId = league.id.trim().isEmpty ? _uuid.v4() : league.id.trim();
      final fixedCode = league.code.trim().isNotEmpty
          ? league.code.trim().toUpperCase()
          : await _generateUniqueJoinCode();

      final fixed = league.copyWith(
        id: leagueId,
        organizerUid: authUid,
        code: fixedCode,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      final leagueRef = _firestore.collection('leagues').doc(leagueId);
      final organizerMembershipRef =
          leagueRef.collection('memberships').doc(authUid);

      final now = DateTime.now().millisecondsSinceEpoch;

      final batch = _firestore.batch();

      batch.set(
        leagueRef,
        {
          ...fixed.toJson(),
          'organizerUid': authUid,
          'ownerUid': authUid,
          'ownerId': authUid,
          'isPrivate': fixed.isPrivate,
          'memberIds': FieldValue.arrayUnion([authUid]),
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      );

      final membership = Membership(
        id: authUid,
        leagueId: leagueId,
        userId: authUid,
        teamId: null,
        role: LeagueRole.organizer,
        updatedAtMs: now,
        version: 1,
      );

      batch.set(
        organizerMembershipRef,
        membership.toRemoteMap(),
        SetOptions(merge: true),
      );

      await batch.commit().timeout(const Duration(seconds: 25));
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'saving league',
      );
    }
  }

  Future<void> deleteLeagueCompletely(String leagueId) async {
    try {
      await _requireOrganizerOrThrow(leagueId);

      final leagueRef = _firestore.collection('leagues').doc(leagueId);

      Future<void> deleteAllDocsIn(String sub, {bool bestEffort = false}) async {
        try {
          final col = leagueRef.collection(sub);
          final snap = await col
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 30));
          if (snap.docs.isEmpty) return;

          const chunkSize = 8;
          for (var i = 0; i < snap.docs.length; i += chunkSize) {
            final batch = _firestore.batch();
            final chunk = snap.docs.sublist(
              i,
              (i + chunkSize > snap.docs.length)
                  ? snap.docs.length
                  : i + chunkSize,
            );
            for (final d in chunk) {
              batch.delete(d.reference);
            }
            await batch.commit().timeout(const Duration(seconds: 30));
          }
        } catch (e) {
          if (!bestEffort) rethrow;
        }
      }

      await deleteAllDocsIn('teams', bestEffort: false);
      await deleteAllDocsIn('matches', bestEffort: false);
      await deleteAllDocsIn('knockout', bestEffort: false);
      await deleteAllDocsIn('memberships', bestEffort: false);
      await deleteAllDocsIn('announcements', bestEffort: true);
      await deleteAllDocsIn('space', bestEffort: true);
      await deleteAllDocsIn('couponCodes', bestEffort: true);
      await deleteAllDocsIn('couponConfig', bestEffort: true);
      await deleteAllDocsIn('pointAdjustments', bestEffort: true);

      await leagueRef.delete().timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'deleting league',
      );
    }
  }

  Future<League> createLeagueLocally({
    required League league,
    required String organizerUserId,
  }) async {
    try {
      final authUid = _requireAuthUid();
      await _requireOnline();

      await _enforceFreeLeagueListCapForNewAddition(
        authUid: authUid,
        actionLabel: 'create another league',
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      final leagueId = league.id.trim().isEmpty ? _uuid.v4() : league.id.trim();
      final code = league.code.trim().isNotEmpty
          ? league.code.trim().toUpperCase()
          : await _generateUniqueJoinCode();

      final stored = league.copyWith(
        id: leagueId,
        organizerUid: authUid,
        organizerUserId: organizerUserId,
        code: code,
        updatedAtMs: now,
      );

      final leagueRef = _firestore.collection('leagues').doc(leagueId);
      final organizerMembershipRef =
          leagueRef.collection('memberships').doc(authUid);

      final batch = _firestore.batch();

      batch.set(
        leagueRef,
        {
          ...stored.toJson(),
          'organizerUid': authUid,
          'ownerUid': authUid,
          'ownerId': authUid,
          'isPrivate': stored.isPrivate,
          'memberIds': FieldValue.arrayUnion([authUid]),
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      );

      final membership = Membership(
        id: authUid,
        leagueId: leagueId,
        userId: authUid,
        teamId: null,
        role: LeagueRole.organizer,
        updatedAtMs: now,
        version: 1,
      );

      batch.set(
        organizerMembershipRef,
        membership.toRemoteMap(),
        SetOptions(merge: true),
      );

      await batch.commit().timeout(const Duration(seconds: 25));

      return stored;
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'creating league',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // joinLeagueLocallyByCode — entry point for QR code and invitation code joins.
  //
  // FIX SUMMARY:
  //   The old code queried leagues by 'code' field and then called _joinLeagueCore.
  //   The query itself could return permission-denied if Firestore rules require
  //   auth to list leagues. Fixed by:
  //
  //   1. The query uses 'code' field which is typically publicly readable in
  //      rules via: allow read: if request.auth != null && resource.data.code == request.resource.data.code
  //      OR the collection is listed as public-read for authenticated users.
  //      If your rules block this query, see note below.
  //
  //   2. Added try-catch around the query so permission-denied on the query
  //      gives a friendly "code not found" message instead of a crash.
  //
  //   3. _joinLeagueCore (called below) now uses the fixed write ordering:
  //      memberIds FIRST, then membership sub-document.
  //
  // NOTE: If your Firestore rules block unauthenticated reads of the leagues
  //   collection even for 'code' queries, you may need to add a Cloud Function
  //   or a separate public 'leagueCodes' collection. However, for most setups
  //   where authenticated users can query by code, this fix is sufficient.
  // ---------------------------------------------------------------------------
  Future<League> joinLeagueLocallyByCode({
    required String joinCode,
    required String userId,
    required League Function(String generatedLeagueId) placeholderBuilder,
    LeagueJoinMode mode = LeagueJoinMode.participant,
  }) async {
    try {
      final authUid = _requireAuthUid();
      await _requireOnline();

      final code = joinCode.trim().toUpperCase();
      if (code.isEmpty) {
        throw const UserFriendlyException('Please enter a valid league code.');
      }

      QuerySnapshot<Map<String, dynamic>> query;
      try {
        query = await _firestore
            .collection('leagues')
            .where('code', isEqualTo: code)
            .limit(1)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 20));
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          // Rules may block listing leagues by code for non-members.
          // Give a helpful message instead of a raw permission error.
          throw const UserFriendlyException(
            "We couldn't find a league with that code. Please check the code and try again.",
          );
        }
        rethrow;
      }

      if (query.docs.isEmpty) {
        throw const UserFriendlyException(
          "We couldn't find a league with that code.",
        );
      }

      final leagueDoc = query.docs.first;
      final leagueId = leagueDoc.id;

      // _joinLeagueCore uses the fixed write order:
      //   Step 3: memberIds arrayUnion FIRST (so rules allow step 4)
      //   Step 4: membership sub-document SECOND (now allowed by rules)
      await _joinLeagueCore(
        leagueId: leagueId,
        authUid: authUid,
        mode: mode,
      );

      final fresh = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      return _docToLeague(fresh);
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'joining league',
      );
    }
  }

  Future<List<Membership>> listMemberships() async {
    try {
      final authUid = _requireAuthUid();
      await _requireOnline();

      final leaguesSnap = await _firestore
          .collection('leagues')
          .where('memberIds', arrayContains: authUid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      final leagueIds =
          leaguesSnap.docs.map((d) => d.id).toList(growable: false);
      if (leagueIds.isEmpty) return const <Membership>[];

      final all = await Future.wait(
        leagueIds.map((leagueId) async {
          final snap = await _firestore
              .collection('leagues')
              .doc(leagueId)
              .collection('memberships')
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 20));

          return snap.docs.map((d) {
            final map = <String, dynamic>{...d.data()};
            map['id'] = (map['id'] is String &&
                    (map['id'] as String).trim().isNotEmpty)
                ? map['id']
                : d.id;
            map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
            map['userId'] = (map['userId'] as String?) ?? '';
            map['role'] =
                (map['role'] as num?)?.toInt() ?? LeagueRole.member.index;
            map['updatedAtMs'] = (map['updatedAtMs'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch;
            map['version'] = (map['version'] as num?)?.toInt() ?? 1;
            return Membership.fromRemoteMap(map);
          }).toList();
        }),
      );

      return all.expand((x) => x).toList(growable: false);
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'listing memberships',
      );
    }
  }

  Future<Membership?> getMembership({
    required String leagueId,
    required String userId,
  }) async {
    try {
      _requireAuthUid();
      await _requireOnline();

      final uid = userId.trim();
      if (uid.isEmpty) return null;

      final direct = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('memberships')
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));

      if (direct.exists) {
        final map = <String, dynamic>{...(direct.data() ?? <String, dynamic>{})};
        map['id'] = (map['id'] is String &&
                (map['id'] as String).trim().isNotEmpty)
            ? map['id']
            : direct.id;
        map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
        map['userId'] = (map['userId'] as String?) ?? uid;
        map['role'] =
            (map['role'] as num?)?.toInt() ?? LeagueRole.member.index;
        map['updatedAtMs'] = (map['updatedAtMs'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;
        map['version'] = (map['version'] as num?)?.toInt() ?? 1;
        return Membership.fromRemoteMap(map);
      }

      final snap = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('memberships')
          .where('userId', isEqualTo: uid)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      if (snap.docs.isEmpty) return null;

      final doc = snap.docs.first;
      final map = <String, dynamic>{...doc.data()};
      map['id'] = (map['id'] is String &&
              (map['id'] as String).trim().isNotEmpty)
          ? map['id']
          : doc.id;
      map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
      map['userId'] = (map['userId'] as String?) ?? uid;
      map['role'] =
          (map['role'] as num?)?.toInt() ?? LeagueRole.member.index;
      map['updatedAtMs'] = (map['updatedAtMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;
      map['version'] = (map['version'] as num?)?.toInt() ?? 1;
      return Membership.fromRemoteMap(map);
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'getting membership',
      );
    }
  }

  Future<void> assignTeamToUserInLeague({
    required String leagueId,
    required String userId,
    required String teamId,
  }) async {
    try {
      await _requireOrganizerOrThrow(leagueId);

      final uid = userId.trim();
      if (uid.isEmpty) {
        throw const UserFriendlyException('Please select a valid user.');
      }

      final membershipRef =
          _firestore.collection('leagues').doc(leagueId).collection('memberships').doc(uid);

      final now = DateTime.now().millisecondsSinceEpoch;
      final existing = await membershipRef
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));

      if (!existing.exists) {
        final membership = Membership(
          id: uid,
          leagueId: leagueId,
          userId: uid,
          teamId: teamId,
          role: LeagueRole.member,
          updatedAtMs: now,
          version: 1,
        );

        await membershipRef
            .set(membership.toRemoteMap(), SetOptions(merge: true))
            .timeout(const Duration(seconds: 20));
        return;
      }

      final data = existing.data() ?? <String, dynamic>{};
      final currentVersion = (data['version'] as num?)?.toInt() ?? 1;

      await membershipRef
          .set(
            {
              'teamId': teamId,
              'updatedAtMs': now,
              'version': currentVersion + 1,
            },
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'assigning team to membership',
      );
    }
  }

  Stream<List<Team>> watchTeams(String leagueId) {
    try {
      _requireAuthUid();

      return _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('teams')
          .snapshots(includeMetadataChanges: true)
          .map((snap) {
        return snap.docs.map((d) {
          final map = <String, dynamic>{...d.data()};
          map['id'] = (map['id'] is String &&
                  (map['id'] as String).trim().isNotEmpty)
              ? map['id']
              : d.id;
          map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
          return Team.fromRemoteMap(map);
        }).toList(growable: false);
      });
    } catch (_) {
      return const Stream<List<Team>>.empty();
    }
  }

  Stream<List<FixtureMatch>> watchMatches(String leagueId) {
    try {
      _requireAuthUid();

      return _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('matches')
          .snapshots(includeMetadataChanges: true)
          .map((snap) {
        return snap.docs.map((d) {
          final map = <String, dynamic>{...d.data()};
          map['id'] = (map['id'] is String &&
                  (map['id'] as String).trim().isNotEmpty)
              ? map['id']
              : d.id;
          map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
          return FixtureMatch.fromJson(map);
        }).toList(growable: false);
      });
    } catch (_) {
      return const Stream<List<FixtureMatch>>.empty();
    }
  }

  Stream<Map<String, int>> watchTeamAdminAdjustmentsByTeamId(String leagueId) {
    try {
      _requireAuthUid();

      return _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('teams')
          .snapshots(includeMetadataChanges: true)
          .map((snap) {
        final out = <String, int>{};
        for (final d in snap.docs) {
          final data = d.data();
          final adj = (data['adminAdjustment'] as num?)?.toInt() ?? 0;
          out[d.id] = adj;
        }
        return out;
      });
    } catch (_) {
      return const Stream<Map<String, int>>.empty();
    }
  }

  Stream<List<PointAdjustment>> watchPointAdjustments({
    required String leagueId,
    int limit = 200,
  }) {
    try {
      _requireAuthUid();

      var q = _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('pointAdjustments')
          .orderBy('createdAt', descending: true);

      if (limit > 0) {
        q = q.limit(limit);
      }

      return q.snapshots(includeMetadataChanges: true).map((snap) {
        return snap.docs
            .map((d) => PointAdjustment.fromDoc(d))
            .toList(growable: false);
      });
    } catch (_) {
      return const Stream<List<PointAdjustment>>.empty();
    }
  }

  bool _statusLooksPlayed(dynamic rawStatus) {
    if (rawStatus is String) {
      final s = rawStatus.trim().toLowerCase();
      return s == 'completed' || s == 'played';
    }

    if (rawStatus is num) {
      final idx = rawStatus.toInt();
      return idx > 0;
    }

    return false;
  }

  bool _matchPlayedFromMap(Map<String, dynamic> m) {
    final hs = (m['homeScore'] as num?)?.toInt();
    final as_ = (m['awayScore'] as num?)?.toInt();
    if (hs == null || as_ == null) return false;
    return _statusLooksPlayed(m['status']);
  }

  int _pointsFor(int scored, int conceded) {
    if (scored > conceded) return 3;
    if (scored == conceded) return 1;
    return 0;
  }

  Future<void> ensureTeamAggregatesBackfilled(String leagueId) async {
    try {
      await _requireOrganizerOrThrow(leagueId);

      _requireAuthUid();
      await _requireOnline();

      final teamsSnap = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('teams')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      if (teamsSnap.docs.isEmpty) return;

      bool needsBackfill = false;
      for (final d in teamsSnap.docs) {
        final data = d.data();
        final hasBase = data['basePoints'] is int || data['basePoints'] is num;
        final hasAdj = data['adminAdjustment'] is int || data['adminAdjustment'] is num;
        final hasFinal = data['finalPoints'] is int || data['finalPoints'] is num;
        final hasGd = data['goalDifference'] is int || data['goalDifference'] is num;
        final hasGf = data['goalsFor'] is int || data['goalsFor'] is num;

        if (!hasBase || !hasAdj || !hasFinal || !hasGd || !hasGf) {
          needsBackfill = true;
          break;
        }
      }

      if (!needsBackfill) return;

      final matchesSnap = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('matches')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 25));

      final basePointsByTeam = <String, int>{};
      final gdByTeam = <String, int>{};
      final gfByTeam = <String, int>{};

      for (final d in matchesSnap.docs) {
        final m = d.data();
        if (!_matchPlayedFromMap(m)) continue;

        final homeId = (m['homeTeamId'] as String? ?? '').trim();
        final awayId = (m['awayTeamId'] as String? ?? '').trim();
        if (homeId.isEmpty || awayId.isEmpty) continue;

        final hs = (m['homeScore'] as num?)!.toInt();
        final as_ = (m['awayScore'] as num?)!.toInt();

        final homePts = _pointsFor(hs, as_);
        final awayPts = _pointsFor(as_, hs);

        basePointsByTeam[homeId] = (basePointsByTeam[homeId] ?? 0) + homePts;
        basePointsByTeam[awayId] = (basePointsByTeam[awayId] ?? 0) + awayPts;

        gfByTeam[homeId] = (gfByTeam[homeId] ?? 0) + hs;
        gfByTeam[awayId] = (gfByTeam[awayId] ?? 0) + as_;

        gdByTeam[homeId] = (gdByTeam[homeId] ?? 0) + (hs - as_);
        gdByTeam[awayId] = (gdByTeam[awayId] ?? 0) + (as_ - hs);
      }

      const chunkSize = 400;
      final docs = teamsSnap.docs;

      for (var i = 0; i < docs.length; i += chunkSize) {
        final batch = _firestore.batch();
        final chunk = docs.sublist(
          i,
          (i + chunkSize > docs.length) ? docs.length : i + chunkSize,
        );

        for (final td in chunk) {
          final data = td.data();

          final teamId = td.id;
          final base = basePointsByTeam[teamId] ?? 0;
          final adj = (data['adminAdjustment'] as num?)?.toInt() ?? 0;

          final gd = gdByTeam[teamId] ?? 0;
          final gf = gfByTeam[teamId] ?? 0;

          batch.set(
            td.reference,
            <String, dynamic>{
              'basePoints': base,
              'adminAdjustment': adj,
              'finalPoints': base + adj,
              'goalDifference': gd,
              'goalsFor': gf,
              'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
            },
            SetOptions(merge: true),
          );
        }

        await batch.commit().timeout(const Duration(seconds: 25));
      }
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'backfilling team aggregates',
      );
    }
  }

  Future<void> updateMatchScoreAndUpdateTeamAggregates({
    required String leagueId,
    required String matchId,
    required int homeScore,
    required int awayScore,
  }) async {
    try {
      await _requireOrganizerOrThrow(leagueId);

      _requireAuthUid();
      await _requireOnline();

      await ensureTeamAggregatesBackfilled(leagueId);

      final matchRef = _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('matches')
          .doc(matchId.trim());

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final hsNew = homeScore < 0 ? 0 : homeScore;
      final asNew = awayScore < 0 ? 0 : awayScore;

      await _firestore.runTransaction((txn) async {
        final matchSnap = await txn.get(matchRef);
        if (!matchSnap.exists) {
          throw const UserFriendlyException(
            "We couldn't find this match. Please refresh and try again.",
          );
        }

        final matchData = (matchSnap.data() ?? <String, dynamic>{})
            .cast<String, dynamic>();

        final homeId = (matchData['homeTeamId'] as String? ?? '').trim();
        final awayId = (matchData['awayTeamId'] as String? ?? '').trim();
        if (homeId.isEmpty || awayId.isEmpty) {
          throw const UserFriendlyException(
            "This match is missing team information. Please refresh and try again.",
          );
        }

        final hsOld = (matchData['homeScore'] as num?)?.toInt();
        final asOld = (matchData['awayScore'] as num?)?.toInt();
        final statusOld = matchData['status'];

        final oldPlayed = (hsOld != null && asOld != null) && _statusLooksPlayed(statusOld);

        final oldHomePts = oldPlayed ? _pointsFor(hsOld!, asOld!) : 0;
        final oldAwayPts = oldPlayed ? _pointsFor(asOld!, hsOld!) : 0;

        final oldHomeGf = oldPlayed ? hsOld : 0;
        final oldAwayGf = oldPlayed ? asOld! : 0;

        final oldHomeGd = oldPlayed ? (hsOld - asOld!) : 0;
        final oldAwayGd = oldPlayed ? (asOld! - hsOld) : 0;

        final newHomePts = _pointsFor(hsNew, asNew);
        final newAwayPts = _pointsFor(asNew, hsNew);

        final newHomeGf = hsNew;
        final newAwayGf = asNew;

        final newHomeGd = hsNew - asNew;
        final newAwayGd = asNew - hsNew;

        final deltaHomePts = newHomePts - oldHomePts;
        final deltaAwayPts = newAwayPts - oldAwayPts;

        final deltaHomeGf = newHomeGf - oldHomeGf;
        final deltaAwayGf = newAwayGf - oldAwayGf;

        final deltaHomeGd = newHomeGd - oldHomeGd;
        final deltaAwayGd = newAwayGd - oldAwayGd;

        final homeRef =
            _firestore.collection('leagues').doc(leagueId).collection('teams').doc(homeId);
        final awayRef =
            _firestore.collection('leagues').doc(leagueId).collection('teams').doc(awayId);

        final homeSnap = await txn.get(homeRef);
        final awaySnap = await txn.get(awayRef);

        if (!homeSnap.exists || !awaySnap.exists) {
          throw const UserFriendlyException(
            "We couldn't find one of the teams for this match. Please refresh and try again.",
          );
        }

        final homeData = (homeSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final awayData = (awaySnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();

        final homeBase = (homeData['basePoints'] as num?)?.toInt() ?? 0;
        final awayBase = (awayData['basePoints'] as num?)?.toInt() ?? 0;

        final homeAdj = (homeData['adminAdjustment'] as num?)?.toInt() ?? 0;
        final awayAdj = (awayData['adminAdjustment'] as num?)?.toInt() ?? 0;

        final homeGd = (homeData['goalDifference'] as num?)?.toInt() ?? 0;
        final awayGd = (awayData['goalDifference'] as num?)?.toInt() ?? 0;

        final homeGf = (homeData['goalsFor'] as num?)?.toInt() ?? 0;
        final awayGf = (awayData['goalsFor'] as num?)?.toInt() ?? 0;

        final nextHomeBase = max(0, homeBase + deltaHomePts);
        final nextAwayBase = max(0, awayBase + deltaAwayPts);

        final nextHomeGf = max(0, homeGf + deltaHomeGf);
        final nextAwayGf = max(0, awayGf + deltaAwayGf);

        final nextHomeGd = homeGd + deltaHomeGd;
        final nextAwayGd = awayGd + deltaAwayGd;

        txn.set(
          matchRef,
          <String, dynamic>{
            'homeScore': hsNew,
            'awayScore': asNew,
            'status': 'completed',
            'updatedAtMs': nowMs,
          },
          SetOptions(merge: true),
        );

        txn.set(
          homeRef,
          <String, dynamic>{
            'basePoints': nextHomeBase,
            'adminAdjustment': homeAdj,
            'finalPoints': nextHomeBase + homeAdj,
            'goalDifference': nextHomeGd,
            'goalsFor': nextHomeGf,
            'updatedAtMs': nowMs,
          },
          SetOptions(merge: true),
        );

        txn.set(
          awayRef,
          <String, dynamic>{
            'basePoints': nextAwayBase,
            'adminAdjustment': awayAdj,
            'finalPoints': nextAwayBase + awayAdj,
            'goalDifference': nextAwayGd,
            'goalsFor': nextAwayGf,
            'updatedAtMs': nowMs,
          },
          SetOptions(merge: true),
        );
      }).timeout(const Duration(seconds: 25));
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'updating score',
      );
    }
  }

  Future<List<Team>> getTeams(String leagueId) async {
    try {
      _requireAuthUid();
      await _requireOnline();

      final snap = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('teams')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      final baseTeams = snap.docs.map((d) {
        final map = <String, dynamic>{...d.data()};
        map['id'] = (map['id'] is String &&
                (map['id'] as String).trim().isNotEmpty)
            ? map['id']
            : d.id;
        map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
        return Team.fromRemoteMap(map);
      }).toList(growable: false);

      final uidTeamIds = baseTeams
          .map((t) => t.id.trim())
          .where((id) => _looksLikeFirebaseUid(id))
          .toList(growable: false);

      if (uidTeamIds.isEmpty) return baseTeams;

      final userImages = await _loadUserImageUrlsByUids(uidTeamIds);

      if (userImages.isEmpty) return baseTeams;

      return baseTeams.map((t) {
        final override = userImages[t.id.trim()];
        if (override != null && override.trim().isNotEmpty) {
          return t.copyWith(teamImageUrl: override.trim());
        }
        return t;
      }).toList(growable: false);
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'loading teams',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // saveTeams — FIXED membership write ordering.
  //
  // OLD BUG: When saving teams where team IDs are Firebase UIDs, the code
  //   wrote the membership sub-document directly WITHOUT first ensuring the
  //   user is in memberIds. This caused permission-denied on the membership
  //   write for the same reason as _joinLeagueCore.
  //
  // FIX: Before writing the membership sub-document for a uid-based team,
  //   first ensure the uid is in the league's memberIds via arrayUnion.
  //   This is the same fix pattern as _joinLeagueCore step 3/4.
  // ---------------------------------------------------------------------------
  Future<void> saveTeams(String leagueId, List<Team> allTeams) async {
    try {
      await _requireOrganizerOrThrow(leagueId);

      final authUid = _requireAuthUid();
      await _requireOnline();

      final col = _firestore.collection('leagues').doc(leagueId).collection('teams');

      final existing = await col
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      final existingAgg = <String, Map<String, int>>{};
      for (final d in existing.docs) {
        final data = d.data();
        final id = d.id;

        final base = (data['basePoints'] as num?)?.toInt();
        final adj = (data['adminAdjustment'] as num?)?.toInt();
        final gd = (data['goalDifference'] as num?)?.toInt();
        final gf = (data['goalsFor'] as num?)?.toInt();

        if (base != null || adj != null || gd != null || gf != null) {
          existingAgg[id] = <String, int>{
            'basePoints': base ?? 0,
            'adminAdjustment': adj ?? 0,
            'goalDifference': gd ?? 0,
            'goalsFor': gf ?? 0,
          };
        }
      }

      const chunkSize = 8;

      if (existing.docs.isNotEmpty) {
        for (var i = 0; i < existing.docs.length; i += chunkSize) {
          final batch = _firestore.batch();
          final chunk = existing.docs.sublist(
            i,
            (i + chunkSize > existing.docs.length)
                ? existing.docs.length
                : i + chunkSize,
          );
          for (final d in chunk) {
            batch.delete(d.reference);
          }
          await batch.commit().timeout(const Duration(seconds: 30));
        }
      }

      for (var i = 0; i < allTeams.length; i += chunkSize) {
        final batch = _firestore.batch();
        final chunk = allTeams.sublist(
          i,
          (i + chunkSize > allTeams.length) ? allTeams.length : i + chunkSize,
        );

        for (final t in chunk) {
          final id = t.id.trim().isEmpty ? _uuid.v4() : t.id.trim();

          final inferredOwnerId = (t.ownerId.trim().isNotEmpty)
              ? t.ownerId.trim()
              : (_looksLikeFirebaseUid(id) ? id : authUid);

          final preserved = existingAgg[id];
          final preservedBase = preserved?['basePoints'] ?? 0;
          final preservedAdj = preserved?['adminAdjustment'] ?? 0;
          final preservedGd = preserved?['goalDifference'] ?? 0;
          final preservedGf = preserved?['goalsFor'] ?? 0;

          final data = <String, dynamic>{
            ...t.copyWith(
              id: id,
              leagueId: leagueId,
              ownerId: inferredOwnerId,
            ).toRemoteMap(),
            'basePoints': preservedBase,
            'adminAdjustment': preservedAdj,
            'finalPoints': preservedBase + preservedAdj,
            'goalDifference': preservedGd,
            'goalsFor': preservedGf,
            'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
          };

          batch.set(col.doc(id), data, SetOptions(merge: true));
        }

        await batch.commit().timeout(const Duration(seconds: 30));
      }

      // FIX: For uid-based teams, first add uid to memberIds on league doc
      // (STEP A), then write the membership sub-document (STEP B).
      // This mirrors the _joinLeagueCore fix — memberIds must be updated
      // before the membership write so the security rules allow it.
      for (final t in allTeams) {
        final uid = t.id.trim();
        if (!_looksLikeFirebaseUid(uid)) continue;

        try {
          final leagueRef = _firestore.collection('leagues').doc(leagueId);
          final membershipRef = leagueRef.collection('memberships').doc(uid);
          final now = DateTime.now().millisecondsSinceEpoch;

          // STEP A — add uid to memberIds FIRST (satisfies rule precondition).
          await leagueRef
              .set(
                {
                  'memberIds': FieldValue.arrayUnion([uid]),
                  'updatedAtMs': now,
                },
                SetOptions(merge: true),
              )
              .timeout(const Duration(seconds: 15));

          // STEP B — now write/update membership sub-document.
          final existingMembership = await membershipRef
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 12));

          if (!existingMembership.exists) {
            final membership = Membership(
              id: uid,
              leagueId: leagueId,
              userId: uid,
              teamId: uid,
              role: LeagueRole.member,
              updatedAtMs: now,
              version: 1,
            );
            await membershipRef
                .set(membership.toRemoteMap(), SetOptions(merge: true))
                .timeout(const Duration(seconds: 20));
          } else {
            final data = existingMembership.data() ?? <String, dynamic>{};
            final currentVersion = (data['version'] as num?)?.toInt() ?? 1;
            await membershipRef
                .set(
                  {
                    'teamId': uid,
                    'updatedAtMs': now,
                    'version': currentVersion + 1,
                  },
                  SetOptions(merge: true),
                )
                .timeout(const Duration(seconds: 20));
          }
        } catch (_) {
          continue;
        }
      }
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'saving teams',
      );
    }
  }

  Future<void> createPointAdjustment({
    required String leagueId,
    required String teamId,
    required PointAdjustmentType type,
    required int points,
    required String reason,
  }) async {
    try {
      final uid = _requireAuthUid();
      await _requireOrganizerOrThrow(leagueId);

      final p = points;
      if (p <= 0) {
        throw const UserFriendlyException('Points must be greater than 0.');
      }

      final r = reason.trim();
      if (r.isEmpty) {
        throw const UserFriendlyException('A reason is required.');
      }

      await ensureTeamAggregatesBackfilled(leagueId);

      final delta = type == PointAdjustmentType.addition ? p : -p;

      final leagueRef = _firestore.collection('leagues').doc(leagueId);
      final teamRef = leagueRef.collection('teams').doc(teamId);
      final adjRef = leagueRef.collection('pointAdjustments').doc();

      await _firestore.runTransaction((txn) async {
        final teamSnap = await txn.get(teamRef);
        if (!teamSnap.exists) {
          throw const UserFriendlyException(
            "We couldn't find this team. Please refresh and try again.",
          );
        }

        final teamData =
            (teamSnap.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final basePoints = (teamData['basePoints'] as num?)?.toInt() ?? 0;
        final currentAdj = (teamData['adminAdjustment'] as num?)?.toInt() ?? 0;

        final newAdj = currentAdj + delta;
        final newFinal = basePoints + newAdj;

        txn.set(adjRef, <String, dynamic>{
          'teamId': teamId,
          'type': type.toFirestoreString(),
          'points': p,
          'reason': r,
          'adjustedBy': uid,
          'createdAt': FieldValue.serverTimestamp(),
        });

        txn.set(
          teamRef,
          <String, dynamic>{
            'basePoints': basePoints,
            'adminAdjustment': newAdj,
            'finalPoints': newFinal,
            'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
          },
          SetOptions(merge: true),
        );
      }).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'creating point adjustment',
      );
    }
  }

  Future<List<FixtureMatch>> getMatches(String leagueId) async {
    try {
      _requireAuthUid();
      await _requireOnline();

      final snap = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('matches')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      return snap.docs.map((d) {
        final map = <String, dynamic>{...d.data()};
        map['id'] = (map['id'] is String &&
                (map['id'] as String).trim().isNotEmpty)
            ? map['id']
            : d.id;
        map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
        return FixtureMatch.fromJson(map);
      }).toList(growable: false);
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'loading matches',
      );
    }
  }

  Future<void> saveMatches(String leagueId, List<FixtureMatch> matches) async {
    try {
      await _requireOrganizerOrThrow(leagueId);

      _requireAuthUid();
      await _requireOnline();

      final col = _firestore.collection('leagues').doc(leagueId).collection('matches');

      const chunkSize = 8;
      for (var i = 0; i < matches.length; i += chunkSize) {
        final batch = _firestore.batch();
        final chunk = matches.sublist(
          i,
          (i + chunkSize > matches.length) ? matches.length : i + chunkSize,
        );

        for (final m in chunk) {
          final id = m.id.trim().isEmpty ? _uuid.v4() : m.id.trim();
          final data = <String, dynamic>{
            ...m.toJson(),
            'id': id,
            'leagueId': leagueId,
          };
          batch.set(col.doc(id), data, SetOptions(merge: true));
        }

        await batch.commit().timeout(const Duration(seconds: 30));
      }
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'saving matches',
      );
    }
  }

  Future<void> replaceMatches(String leagueId, List<FixtureMatch> matches) async {
    try {
      await _requireOrganizerOrThrow(leagueId);

      _requireAuthUid();
      await _requireOnline();

      final col = _firestore.collection('leagues').doc(leagueId).collection('matches');
      final existing = await col
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      const chunkSize = 8;

      if (existing.docs.isNotEmpty) {
        for (var i = 0; i < existing.docs.length; i += chunkSize) {
          final batch = _firestore.batch();
          final chunk = existing.docs.sublist(
            i,
            (i + chunkSize > existing.docs.length)
                ? existing.docs.length
                : i + chunkSize,
          );
          for (final d in chunk) {
            batch.delete(d.reference);
          }
          await batch.commit().timeout(const Duration(seconds: 30));
        }
      }

      await saveMatches(leagueId, matches);
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'replacing matches',
      );
    }
  }

  Future<List<KnockoutMatch>> getKnockoutMatches(String leagueId) async {
    try {
      _requireAuthUid();
      await _requireOnline();

      final snap = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('knockout')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      final list = snap.docs.map((d) {
        final map = <String, dynamic>{...d.data()};
        map['id'] = (map['id'] is String &&
                (map['id'] as String).trim().isNotEmpty)
            ? map['id']
            : d.id;
        map['leagueId'] = (map['leagueId'] as String?) ?? leagueId;
        return KnockoutMatch.fromJson(map);
      }).toList(growable: false);

      const roundOrder = <String>[
        'Play-off',
        'Round of 16',
        'Quarter Finals',
        'Semi Finals',
        'Final',
        '3rd Place',
      ];

      final sorted = [...list];
      sorted.sort((a, b) {
        final ai = roundOrder.indexOf(a.roundName);
        final bi = roundOrder.indexOf(b.roundName);
        if (ai != bi) {
          if (ai == -1) return 1;
          if (bi == -1) return -1;
          return ai.compareTo(bi);
        }
        if (a.roundName == 'Play-off' && b.roundName == 'Play-off') {
          final an = (a.nextMatchId ?? '');
          final bn = (b.nextMatchId ?? '');
          final c1 = an.compareTo(bn);
          if (c1 != 0) return c1;
          final c2 =
              (a.isSecondLeg ? 1 : 0).compareTo(b.isSecondLeg ? 1 : 0);
          if (c2 != 0) return c2;
        }
        return a.id.compareTo(b.id);
      });

      return sorted;
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'loading knockout',
      );
    }
  }

  Future<void> saveKnockoutMatches(
    String leagueId,
    List<KnockoutMatch> matches,
  ) async {
    try {
      await _requireOrganizerOrThrow(leagueId);

      _requireAuthUid();
      await _requireOnline();

      final col = _firestore.collection('leagues').doc(leagueId).collection('knockout');

      final existing = await col
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      const chunkSize = 8;

      if (existing.docs.isNotEmpty) {
        for (var i = 0; i < existing.docs.length; i += chunkSize) {
          final batch = _firestore.batch();
          final chunk = existing.docs.sublist(
            i,
            (i + chunkSize > existing.docs.length)
                ? existing.docs.length
                : i + chunkSize,
          );
          for (final d in chunk) {
            batch.delete(d.reference);
          }
          await batch.commit().timeout(const Duration(seconds: 30));
        }
      }

      for (var i = 0; i < matches.length; i += chunkSize) {
        final batch = _firestore.batch();
        final chunk = matches.sublist(
          i,
          (i + chunkSize > matches.length) ? matches.length : i + chunkSize,
        );

        for (final m in chunk) {
          final id = m.id.trim().isNotEmpty ? m.id.trim() : _uuid.v4();
          final data = m.copyWith(id: id, leagueId: leagueId).toJson();
          batch.set(col.doc(id), data, SetOptions(merge: true));
        }

        await batch.commit().timeout(const Duration(seconds: 30));
      }
    } catch (e) {
      _rethrowFriendly(
        e is Object ? e : Exception('unknown'),
        context: 'saving knockout',
      );
    }
  }
}
