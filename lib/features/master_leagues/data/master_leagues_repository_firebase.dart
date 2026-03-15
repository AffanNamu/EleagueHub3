import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/master_league.dart';
import '../domain/master_league_plan.dart';

class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

class MasterLeaguesRepositoryFirebase {
  MasterLeaguesRepositoryFirebase({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Uuid _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('master_leagues');

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _payments =>
      _firestore.collection('payments');

  CollectionReference<Map<String, dynamic>> get _attempts =>
      _firestore.collection('payment_attempts');

  static const Set<String> _allowedSocialKeys = <String>{
    'website',
    'facebook',
    'instagram',
    'x',
    'twitter',
    'discord',
    'youtube',
    'twitch',
    'tiktok',
  };

  String _requireAuthUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const UserFriendlyException('Please sign in and try again.');
    }
    return uid;
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  static bool _looksLikeShareId(String raw) {
    final s = raw.trim();
    return RegExp(r'^eS[A-Za-z0-9]{4,12}$').hasMatch(s);
  }

  Never _rethrowFriendly(Object error) {
    if (error is UserFriendlyException) throw error;

    if (error is SocketException || error is HandshakeException) {
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
          '[MasterLeaguesRepo] FirebaseException code=${error.code} message=${error.message}',
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
            'You don\'t have access to this Master League. Please make sure your payment is completed and verified, then try again.',
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

    throw const UserFriendlyException(
      'Something went wrong. Please try again.',
    );
  }

  String _trimUrl(String value) {
    final out = value.trim();
    return out.length <= 2000 ? out : out.substring(0, 2000);
  }

  String _trimText(String value, int max) {
    final out = value.trim();
    return out.length <= max ? out : out.substring(0, max);
  }

  Map<String, String> _sanitizeSocialLinks(Map<String, String> input) {
    final out = <String, String>{};
    for (final entry in input.entries) {
      final key = entry.key.trim().toLowerCase();
      if (!_allowedSocialKeys.contains(key)) continue;
      final value = _trimUrl(entry.value);
      if (value.isNotEmpty) {
        out[key] = value;
      }
    }
    return out;
  }

  OrganizerProfile _normalizedProfile(OrganizerProfile profile) {
    return OrganizerProfile(
      bannerUrl: _trimUrl(profile.bannerUrl),
      logoUrl: _trimUrl(profile.logoUrl),
      bio: _trimText(profile.bio, 2000),
      socialLinks: _sanitizeSocialLinks(profile.socialLinks),
      badge: _trimText(profile.badge, 80),
    );
  }

  Stream<List<MasterLeague>> watchMyMasterLeagues() {
    try {
      final uid = _requireAuthUid();

      return _col
          .where('memberIds', arrayContains: uid)
          .snapshots(includeMetadataChanges: true)
          .map((snap) {
        final list = snap.docs
            .map((d) => MasterLeague.fromMap(d.id, d.data()))
            .toList(growable: false);

        final sorted = [...list];
        sorted.sort((a, b) {
          final at = a.createdAt;
          final bt = b.createdAt;
          if (at == null && bt == null) {
            return b.updatedAtMs.compareTo(a.updatedAtMs);
          }
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });

        return sorted;
      });
    } catch (_) {
      return const Stream<List<MasterLeague>>.empty();
    }
  }

  Stream<List<MasterLeague>> watchCreatedMasterLeagues() {
    try {
      final uid = _requireAuthUid();

      return _col
          .where('ownerId', isEqualTo: uid)
          .snapshots(includeMetadataChanges: true)
          .map((snap) {
        final list = snap.docs
            .map((d) => MasterLeague.fromMap(d.id, d.data()))
            .toList(growable: false);
        list.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
        return list;
      });
    } catch (_) {
      return const Stream<List<MasterLeague>>.empty();
    }
  }

  Stream<List<MasterLeague>> watchJoinedMasterLeagues() {
    try {
      final uid = _requireAuthUid();

      return _col
          .where('memberIds', arrayContains: uid)
          .snapshots(includeMetadataChanges: true)
          .map((snap) {
        final list = snap.docs
            .map((d) => MasterLeague.fromMap(d.id, d.data()))
            .where((ml) => ml.ownerId.trim() != uid)
            .toList(growable: false);
        list.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
        return list;
      });
    } catch (_) {
      return const Stream<List<MasterLeague>>.empty();
    }
  }

  Future<MasterLeague?> getById(String id) async {
    try {
      _requireAuthUid();

      final trimmed = id.trim();
      if (trimmed.isEmpty) return null;

      final snap = await _col
          .doc(trimmed)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      if (!snap.exists) return null;
      return MasterLeague.fromDoc(snap);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> checkMasterLeagueLimitOrThrow(MasterLeaguePlan plan) async {
    final uid = _requireAuthUid();

    final snap = await _firestore
        .collection('master_leagues')
        .where('ownerId', isEqualTo: uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));

    final count = snap.docs.length;

    if (!plan.unlimitedMasterLeagues && count >= plan.maxMasterLeagues) {
      throw UserFriendlyException(
        'You have reached the limit of ${plan.maxMasterLeagues} master league${plan.maxMasterLeagues == 1 ? '' : 's'} for the ${plan.displayName} plan. Upgrade to a higher plan to create more.',
      );
    }
  }

  Future<void> checkLeagueLimitOrThrow(String masterLeagueId) async {
    final ml = await getById(masterLeagueId);
    if (ml == null) {
      throw const UserFriendlyException(
        "We couldn't find that Master League.",
      );
    }

    if (ml.plan.unlimitedCompetitions) return;

    final snap = await _firestore
        .collection('leagues')
        .where('masterLeagueId', isEqualTo: masterLeagueId.trim())
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));

    final count = snap.docs.length;

    if (count >= ml.maxLeagues) {
      throw UserFriendlyException(
        'You have reached the limit of ${ml.maxLeagues} competitions for your ${ml.plan.displayName} plan. Upgrade your plan to create more.',
      );
    }
  }

  String _masterLeagueSlotId({
    required String ownerUid,
    required int slot,
  }) {
    return 'ml_${ownerUid}_$slot';
  }

  Future<String> _allocateMasterLeagueIdForPlan(MasterLeaguePlan plan) async {
    final uid = _requireAuthUid();

    if (plan == MasterLeaguePlan.elite) {
      return _uuid.v4();
    }

    await checkMasterLeagueLimitOrThrow(plan);

    final ownedSnap = await _firestore
        .collection('master_leagues')
        .where('ownerId', isEqualTo: uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));

    final existingIds = ownedSnap.docs
        .map((d) => d.id.trim())
        .where((s) => s.isNotEmpty)
        .toSet();

    for (int slot = 1; slot <= plan.maxMasterLeagues; slot++) {
      final candidate = _masterLeagueSlotId(ownerUid: uid, slot: slot);
      if (!existingIds.contains(candidate)) {
        return candidate;
      }
    }

    throw UserFriendlyException(
      'You have reached the limit of ${plan.maxMasterLeagues} master league${plan.maxMasterLeagues == 1 ? '' : 's'} for the ${plan.displayName} plan.',
    );
  }

  Future<MasterLeague> create({
    required String name,
    MasterLeaguePlan plan = MasterLeaguePlan.basic,
  }) async {
    try {
      final uid = _requireAuthUid();

      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        throw const UserFriendlyException(
          'Please enter a name for your Master League.',
        );
      }
      if (trimmed.length > 60) {
        throw const UserFriendlyException(
          'Master League name is too long.',
        );
      }

      final id = await _allocateMasterLeagueIdForPlan(plan);
      final ref = _col.doc(id);
      final now = _nowMs();

      final docData = <String, dynamic>{
        'name': trimmed,
        'ownerId': uid,
        'createdAt': Timestamp.now(),
        'purchaseStatus': 'active',
        'memberIds': <String>[uid],
        'roles': <String, String>{uid: 'owner'},
        'staffShareIds': <String, String>{},
        'updatedAtMs': now,
        'plan': plan.id,
        'bannerUrl': '',
        'logoUrl': '',
        'bio': '',
        'badge': '',
        'socialLinks': <String, String>{},
        'totalTournamentsCreated': 0,
        'totalParticipantsTeams': 0,
        'totalMatches': 0,
        'createdViaAttemptId': '',
        'sourcePaymentId': '',
        'sourceReceiptId': '',
      };

      await ref.set(docData, SetOptions(merge: false)).timeout(
            const Duration(seconds: 20),
          );

      final fresh = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      return MasterLeague.fromDoc(fresh);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<MasterLeague> createAfterVerifiedPayment({
    required String masterLeagueName,
    required MasterLeaguePlan plan,
    required String attemptId,
    required String paymentId,
    required String receiptId,
    required MasterLeagueCompetitionDraft competition,
  }) async {
    try {
      final uid = _requireAuthUid();
      final safeName = masterLeagueName.trim();
      final safeAttemptId = attemptId.trim();
      final safePaymentId = paymentId.trim();
      final safeReceiptId = receiptId.trim();

      if (safeName.isEmpty) {
        throw const UserFriendlyException('Please enter a master league name.');
      }
      if (safeName.length > 60) {
        throw const UserFriendlyException('Master League name is too long.');
      }
      if (competition.name.trim().isEmpty) {
        throw const UserFriendlyException('Please enter a competition name.');
      }
      if (competition.name.trim().length > 60) {
        throw const UserFriendlyException('Competition name is too long.');
      }
      if (competition.maxParticipants < 2) {
        throw const UserFriendlyException(
          'Max participants must be at least 2.',
        );
      }
      if (competition.entryFee < 0) {
        throw const UserFriendlyException('Entry fee cannot be negative.');
      }
      if (safeAttemptId.isEmpty || safePaymentId.isEmpty || safeReceiptId.isEmpty) {
        throw const UserFriendlyException(
          'Payment verification is incomplete. Please try again.',
        );
      }

      await checkMasterLeagueLimitOrThrow(plan);

      final paymentSnap = await _payments
          .doc(safePaymentId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      if (!paymentSnap.exists) {
        throw const UserFriendlyException(
          'Verified payment record was not found.',
        );
      }

      final paymentData = (paymentSnap.data() ?? <String, dynamic>{});
      final paymentUid = (paymentData['userId'] as String? ?? '').trim();
      if (paymentUid != uid) {
        throw const UserFriendlyException(
          'This payment does not belong to your account.',
        );
      }

      final verification = (paymentData['verification'] is Map)
          ? (paymentData['verification'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final verified = verification['verified'] == true;
      if (!verified) {
        throw const UserFriendlyException(
          'Payment is not verified yet. Please try again.',
        );
      }

      final fulfilledMasterLeagueId =
          (paymentData['fulfilledMasterLeagueId'] as String? ?? '').trim();
      if (fulfilledMasterLeagueId.isNotEmpty) {
        final existing = await getById(fulfilledMasterLeagueId);
        if (existing != null) {
          return existing;
        }
      }

      final attemptSnap = await _attempts
          .doc(safeAttemptId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      if (!attemptSnap.exists) {
        throw const UserFriendlyException(
          'Payment attempt was not found.',
        );
      }

      final attemptData = (attemptSnap.data() ?? <String, dynamic>{});
      final attemptUid = (attemptData['userId'] as String? ?? '').trim();
      if (attemptUid != uid) {
        throw const UserFriendlyException(
          'This payment attempt does not belong to your account.',
        );
      }

      final id = await _allocateMasterLeagueIdForPlan(plan);
      final ref = _col.doc(id);
      final now = _nowMs();

      await _firestore.runTransaction((txn) async {
        final payRef = _payments.doc(safePaymentId);
        final attRef = _attempts.doc(safeAttemptId);
        final mlRef = _col.doc(id);

        final payDoc = await txn.get(payRef);
        if (!payDoc.exists) {
          throw const UserFriendlyException('Verified payment record was not found.');
        }

        final payMap = (payDoc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final payUid = (payMap['userId'] as String? ?? '').trim();
        if (payUid != uid) {
          throw const UserFriendlyException(
            'This payment does not belong to your account.',
          );
        }

        final payVerification = (payMap['verification'] is Map)
            ? (payMap['verification'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        if (payVerification['verified'] != true) {
          throw const UserFriendlyException(
            'Payment is not verified yet. Please try again.',
          );
        }

        final alreadyFulfilled =
            (payMap['fulfilledMasterLeagueId'] as String? ?? '').trim();
        if (alreadyFulfilled.isNotEmpty) {
          return;
        }

        final attDoc = await txn.get(attRef);
        if (!attDoc.exists) {
          throw const UserFriendlyException('Payment attempt was not found.');
        }

        final attMap = (attDoc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
        final attUid = (attMap['userId'] as String? ?? '').trim();
        if (attUid != uid) {
          throw const UserFriendlyException(
            'This payment attempt does not belong to your account.',
          );
        }

        final mlDoc = await txn.get(mlRef);
        if (mlDoc.exists) {
          throw const UserFriendlyException(
            'A Master League already exists for this payment.',
          );
        }

        txn.set(
          mlRef,
          <String, dynamic>{
            'name': safeName,
            'ownerId': uid,
            'createdAt': FieldValue.serverTimestamp(),
            'purchaseStatus': 'active',
            'memberIds': <String>[uid],
            'roles': <String, String>{uid: 'owner'},
            'staffShareIds': <String, String>{},
            'updatedAtMs': now,
            'plan': plan.id,
            'bannerUrl': '',
            'logoUrl': '',
            'bio': '',
            'badge': '',
            'socialLinks': <String, String>{},
            'totalTournamentsCreated': 0,
            'totalParticipantsTeams': 0,
            'totalMatches': 0,
            'createdViaAttemptId': safeAttemptId,
            'sourcePaymentId': safePaymentId,
            'sourceReceiptId': safeReceiptId,
            'initialCompetition': competition.toMap(),
          },
        );

        txn.update(
          payRef,
          <String, dynamic>{
            'fulfilledMasterLeagueId': id,
            'fulfilledAtMs': now,
            'updatedAtMs': now,
          },
        );

        final nextAttempt = Map<String, dynamic>.from(attMap)
          ..addAll(<String, dynamic>{
            'status': 'fulfilled',
            'fulfilledMasterLeagueId': id,
            'receiptId': safeReceiptId,
            'paymentId': safePaymentId,
            'updatedAtMs': now,
          });

        txn.set(attRef, nextAttempt, SetOptions(merge: false));
      });

      final fresh = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));
      if (!fresh.exists) {
        throw const UserFriendlyException(
          'Master League creation could not be confirmed. Please refresh.',
        );
      }
      return MasterLeague.fromDoc(fresh);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[MasterLeaguesRepo] createAfterVerifiedPayment failed: $e');
      }
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> requireOwnerOrThrow(String masterLeagueId) async {
    try {
      final uid = _requireAuthUid();
      final id = masterLeagueId.trim();
      if (id.isEmpty) {
        throw const UserFriendlyException(
          "We couldn't find that Master League. Please refresh and try again.",
        );
      }

      final snap = await _col
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
          (data['ownerId'] as String? ?? data['ownerUid'] as String? ?? '').trim();

      if (ownerId.isEmpty || ownerId != uid) {
        throw const UserFriendlyException(
          'Only the Master League owner can perform this action.',
        );
      }
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<String?> resolveUidFromShareId(String shareId) async {
    try {
      _requireAuthUid();

      final sid = shareId.trim();
      if (!_looksLikeShareId(sid)) return null;

      final snap = await _users
          .where('shareId', isEqualTo: sid)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      if (snap.docs.isEmpty) return null;
      final uid = snap.docs.first.id.trim();
      return uid.isEmpty ? null : uid;
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> addStaffByShortId({
    required String masterLeagueId,
    required String shortId,
    required String role,
  }) async {
    try {
      await requireOwnerOrThrow(masterLeagueId);

      final ownerUid = _requireAuthUid();
      final normalizedRole = role.trim().toLowerCase();
      if (normalizedRole != 'admin' && normalizedRole != 'moderator') {
        throw const UserFriendlyException('Invalid role.');
      }

      final sid = shortId.trim();
      if (!_looksLikeShareId(sid)) {
        throw const UserFriendlyException(
          'Invalid short id. Example: eS44e35f',
        );
      }

      final uid = await resolveUidFromShareId(sid);
      if (uid == null || uid.isEmpty) {
        throw const UserFriendlyException(
          'We could not find a user with that short id.',
        );
      }

      if (uid == ownerUid) {
        throw const UserFriendlyException(
          'You are already the owner of this Master League.',
        );
      }

      final now = _nowMs();
      await _col.doc(masterLeagueId.trim()).update(<String, dynamic>{
        'memberIds': FieldValue.arrayUnion([uid]),
        'roles.$uid': normalizedRole,
        'staffShareIds.$uid': sid,
        'updatedAtMs': now,
      }).timeout(const Duration(seconds: 12));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> addStaffByShareId({
    required String masterLeagueId,
    required String shareId,
    required MasterLeagueStaffRole role,
  }) async {
    await addStaffByShortId(
      masterLeagueId: masterLeagueId,
      shortId: shareId,
      role: role.id,
    );
  }

  Future<void> changeStaffRole({
    required String masterLeagueId,
    required String memberUid,
    required MasterLeagueStaffRole role,
    String? shareId,
  }) async {
    try {
      await requireOwnerOrThrow(masterLeagueId);

      final uid = memberUid.trim();
      if (uid.isEmpty) {
        throw const UserFriendlyException('Invalid user.');
      }

      final ml = await getById(masterLeagueId);
      if (ml != null && ml.ownerId.trim() == uid) {
        throw const UserFriendlyException('You cannot change the owner.');
      }

      final now = _nowMs();
      final data = <String, dynamic>{
        'memberIds': FieldValue.arrayUnion([uid]),
        'roles.$uid': role.id,
        'updatedAtMs': now,
      };

      final sid = shareId?.trim() ?? '';
      if (sid.isNotEmpty && _looksLikeShareId(sid)) {
        data['staffShareIds.$uid'] = sid;
      }

      await _col
          .doc(masterLeagueId.trim())
          .update(data)
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> removeStaffRole({
    required String masterLeagueId,
    required String staffUid,
  }) async {
    try {
      await requireOwnerOrThrow(masterLeagueId);

      final uid = staffUid.trim();
      if (uid.isEmpty) {
        throw const UserFriendlyException('Invalid user.');
      }

      final ml = await getById(masterLeagueId);
      if (ml != null && ml.ownerId.trim() == uid) {
        throw const UserFriendlyException('You cannot change the owner.');
      }

      final now = _nowMs();
      await _col.doc(masterLeagueId.trim()).update(<String, dynamic>{
        'roles.$uid': FieldValue.delete(),
        'staffShareIds.$uid': FieldValue.delete(),
        'updatedAtMs': now,
      }).timeout(const Duration(seconds: 12));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> removeStaff({
    required String masterLeagueId,
    required String memberUid,
  }) async {
    await removeStaffRole(
      masterLeagueId: masterLeagueId,
      staffUid: memberUid,
    );
  }

  Future<void> updateOrganizerProfile({
    required String masterLeagueId,
    required OrganizerProfile profile,
  }) async {
    try {
      await requireOwnerOrThrow(masterLeagueId);

      final safe = _normalizedProfile(profile);

      await _col.doc(masterLeagueId.trim()).update(<String, dynamic>{
        'bannerUrl': safe.bannerUrl,
        'logoUrl': safe.logoUrl,
        'bio': safe.bio,
        'badge': safe.badge,
        'socialLinks': safe.socialLinks,
        'updatedAtMs': _nowMs(),
      }).timeout(const Duration(seconds: 15));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> saveOrganizerProfile({
    required String masterLeagueId,
    String? bannerUrl,
    String? logoUrl,
    String? bio,
    String? badge,
    Map<String, String>? socialLinks,
  }) async {
    try {
      await requireOwnerOrThrow(masterLeagueId);

      final current = await getById(masterLeagueId);
      final existing = current?.organizerProfile ?? const OrganizerProfile.empty();

      final next = _normalizedProfile(
        existing.copyWith(
          bannerUrl: bannerUrl ?? existing.bannerUrl,
          logoUrl: logoUrl ?? existing.logoUrl,
          bio: bio ?? existing.bio,
          badge: badge ?? existing.badge,
          socialLinks: socialLinks ?? existing.socialLinks,
        ),
      );

      await updateOrganizerProfile(
        masterLeagueId: masterLeagueId,
        profile: next,
      );
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> rename({
    required String masterLeagueId,
    required String newName,
  }) async {
    try {
      await requireOwnerOrThrow(masterLeagueId);

      final name = newName.trim();
      if (name.isEmpty) {
        throw const UserFriendlyException('Please enter a name.');
      }
      if (name.length > 60) {
        throw const UserFriendlyException('Name is too long.');
      }

      await _col.doc(masterLeagueId.trim()).update(<String, dynamic>{
        'name': name,
        'updatedAtMs': _nowMs(),
      }).timeout(const Duration(seconds: 12));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> addMember({
    required String masterLeagueId,
    required String memberUid,
  }) async {
    try {
      await requireOwnerOrThrow(masterLeagueId);

      final m = memberUid.trim();
      if (m.isEmpty || m.length < 10) {
        throw const UserFriendlyException('Invalid member.');
      }

      await _col.doc(masterLeagueId.trim()).update(<String, dynamic>{
        'memberIds': FieldValue.arrayUnion([m]),
        'updatedAtMs': _nowMs(),
      }).timeout(const Duration(seconds: 12));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> removeMember({
    required String masterLeagueId,
    required String memberUid,
  }) async {
    try {
      await requireOwnerOrThrow(masterLeagueId);

      final m = memberUid.trim();
      if (m.isEmpty) {
        throw const UserFriendlyException('Invalid member.');
      }

      final ml = await getById(masterLeagueId);
      if (ml != null && ml.ownerId.trim() == m) {
        throw const UserFriendlyException(
          'The owner cannot be removed from the Master League.',
        );
      }

      await _col.doc(masterLeagueId.trim()).update(<String, dynamic>{
        'memberIds': FieldValue.arrayRemove([m]),
        'roles.$m': FieldValue.delete(),
        'staffShareIds.$m': FieldValue.delete(),
        'updatedAtMs': _nowMs(),
      }).timeout(const Duration(seconds: 12));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> delete(String masterLeagueId) async {
    try {
      await requireOwnerOrThrow(masterLeagueId);

      final id = masterLeagueId.trim();

      try {
        final childLeagues = await _firestore
            .collection('leagues')
            .where('masterLeagueId', isEqualTo: id)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 15));

        if (childLeagues.docs.isNotEmpty) {
          final batch = _firestore.batch();
          for (final doc in childLeagues.docs) {
            batch.update(doc.reference, <String, dynamic>{
              'masterLeagueId': FieldValue.delete(),
            });
          }
          await batch.commit().timeout(const Duration(seconds: 15));
        }
      } catch (_) {}

      await _col.doc(id).delete().timeout(const Duration(seconds: 15));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }
}
