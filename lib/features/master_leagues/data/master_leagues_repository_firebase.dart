import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/competition_template.dart';
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

  CollectionReference<Map<String, dynamic>> get _verificationRequests =>
      _firestore.collection('master_league_verification_requests');

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

  void _log(Object error, [StackTrace? st]) {
    if (!kDebugMode) return;
    debugPrint('[MasterLeaguesRepo] $error');
    if (st != null) debugPrint('$st');
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

  CollectionReference<Map<String, dynamic>> _followersCol(String masterLeagueId) {
    return _col.doc(masterLeagueId.trim()).collection('followers');
  }

  CollectionReference<Map<String, dynamic>> _templatesCol(String masterLeagueId) {
    return _col.doc(masterLeagueId.trim()).collection('competition_templates');
  }

  Stream<List<MasterLeague>> watchMyMasterLeagues() {
    try {
      final uid = _requireAuthUid();

      return _col.snapshots(includeMetadataChanges: true).map((snap) {
        final list = snap.docs
            .map((d) => MasterLeague.fromMap(d.id, d.data()))
            .where((ml) =>
                ml.ownerId.trim() == uid ||
                ml.memberIds.contains(uid) ||
                ml.roles.containsKey(uid))
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
      }).handleError((error, st) {
        _log(error, st);
      });
    } catch (_) {
      return Stream<List<MasterLeague>>.value(const <MasterLeague>[]);
    }
  }

  Stream<List<MasterLeague>> watchCreatedMasterLeagues() {
    try {
      final uid = _requireAuthUid();

      return _col.snapshots(includeMetadataChanges: true).map((snap) {
        final list = snap.docs
            .map((d) => MasterLeague.fromMap(d.id, d.data()))
            .where((ml) => ml.ownerId.trim() == uid)
            .toList(growable: false);
        list.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
        return list;
      }).handleError((error, st) {
        _log(error, st);
      });
    } catch (_) {
      return Stream<List<MasterLeague>>.value(const <MasterLeague>[]);
    }
  }

  Stream<List<MasterLeague>> watchJoinedMasterLeagues() {
    try {
      final uid = _requireAuthUid();

      return _col.snapshots(includeMetadataChanges: true).map((snap) {
        final list = snap.docs
            .map((d) => MasterLeague.fromMap(d.id, d.data()))
            .where((ml) =>
                ml.ownerId.trim() != uid &&
                (ml.memberIds.contains(uid) || ml.roles.containsKey(uid)))
            .toList(growable: false);
        list.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
        return list;
      }).handleError((error, st) {
        _log(error, st);
      });
    } catch (_) {
      return Stream<List<MasterLeague>>.value(const <MasterLeague>[]);
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

  Stream<bool> watchIsFollowing(String masterLeagueId) {
    try {
      final uid = _requireAuthUid();
      final id = masterLeagueId.trim();
      if (id.isEmpty) return Stream<bool>.value(false);

      return _followersCol(id).doc(uid).snapshots().map((snap) => snap.exists);
    } catch (_) {
      return Stream<bool>.value(false);
    }
  }

  Stream<int> watchFollowersCount(String masterLeagueId) {
    try {
      _requireAuthUid();
      final id = masterLeagueId.trim();
      if (id.isEmpty) return Stream<int>.value(0);

      return _col.doc(id).snapshots().map((snap) {
        final data = snap.data() ?? <String, dynamic>{};
        final v = data['followersCount'];
        if (v is int) return v;
        if (v is num) return v.toInt();
        return 0;
      });
    } catch (_) {
      return Stream<int>.value(0);
    }
  }

  Stream<List<CompetitionTemplate>> watchCompetitionTemplates(
      String masterLeagueId) {
    try {
      _requireAuthUid();
      final id = masterLeagueId.trim();
      if (id.isEmpty) {
        return Stream<List<CompetitionTemplate>>.value(
          const <CompetitionTemplate>[],
        );
      }

      return _templatesCol(id)
          .orderBy('updatedAtMs', descending: true)
          .snapshots(includeMetadataChanges: true)
          .map((snap) {
        return snap.docs
            .map((d) => CompetitionTemplate.fromMap(d.data()))
            .toList(growable: false);
      });
    } catch (_) {
      return Stream<List<CompetitionTemplate>>.value(
        const <CompetitionTemplate>[],
      );
    }
  }

  Future<List<MasterLeague>> discoverFeaturedOrganizers({
    int limit = 8,
  }) async {
    try {
      _requireAuthUid();

      final adminsSnap = await _firestore
          .collection('app')
          .doc('featured_organizers')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 12));

      final data = adminsSnap.data() ?? <String, dynamic>{};
      final idsRaw = data['masterLeagueIds'];
      final ids = <String>[];

      if (idsRaw is List) {
        for (final v in idsRaw) {
          final s = (v ?? '').toString().trim();
          if (s.isNotEmpty) ids.add(s);
        }
      }

      if (ids.isNotEmpty) {
        final out = <MasterLeague>[];
        const int chunkSize = 10;

        for (int i = 0; i < ids.length; i += chunkSize) {
          final chunk = ids.sublist(
            i,
            (i + chunkSize < ids.length) ? i + chunkSize : ids.length,
          );

          try {
            final snap = await _col
                .where(FieldPath.documentId, whereIn: chunk)
                .get(const GetOptions(source: Source.server))
                .timeout(const Duration(seconds: 15));

            out.addAll(
              snap.docs.map((d) => MasterLeague.fromMap(d.id, d.data())),
            );
          } catch (e, st) {
            _log(e, st);
          }
        }

        if (out.isNotEmpty) {
          out.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
          return out.take(limit).toList(growable: false);
        }
      }

      return await discoverVerifiedOrganizers(limit: limit);
    } catch (e) {
      _log(e);
      return await discoverVerifiedOrganizers(limit: limit);
    }
  }

  Future<List<MasterLeague>> discoverVerifiedOrganizers({
    int limit = 12,
  }) async {
    try {
      _requireAuthUid();

      final snap = await _col
          .where('verifiedBadge', isEqualTo: true)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      final list = snap.docs
          .map((d) => MasterLeague.fromMap(d.id, d.data()))
          .toList(growable: false);

      list.sort((a, b) {
        final followersCmp = b.followersCount.compareTo(a.followersCount);
        if (followersCmp != 0) return followersCmp;
        return b.updatedAtMs.compareTo(a.updatedAtMs);
      });

      return list.take(limit).toList(growable: false);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<List<MasterLeague>> discoverRecentActiveOrganizers({
    int limit = 12,
  }) async {
    try {
      _requireAuthUid();

      final snap = await _col
          .orderBy('updatedAtMs', descending: true)
          .limit(limit * 2)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      final list = snap.docs
          .map((d) => MasterLeague.fromMap(d.id, d.data()))
          .where((ml) =>
              ml.isVerifiedOrganizer ||
              ml.organizerProfile.bio.trim().isNotEmpty)
          .toList(growable: false);

      return list.take(limit).toList(growable: false);
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
    try {
      final uid = _requireAuthUid();
      final id = masterLeagueId.trim();
      if (id.isEmpty) {
        throw const UserFriendlyException(
          "We couldn't find that Master League.",
        );
      }

      final ml = await getById(id);
      if (ml == null) {
        throw const UserFriendlyException(
          "We couldn't find that Master League.",
        );
      }
      if (ml.ownerId.trim() != uid) {
        throw const UserFriendlyException(
          'Only the Master League owner can create competitions.',
        );
      }
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
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
          throw const UserFriendlyException(
            'Verified payment record was not found.',
          );
        }

        final payMap =
            (payDoc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
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

        final attMap =
            (attDoc.data() ?? <String, dynamic>{}).cast<String, dynamic>();
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
            'followersCount': 0,
            'createdViaAttemptId': safeAttemptId,
            'sourcePaymentId': safePaymentId,
            'sourceReceiptId': safeReceiptId,
            'initialCompetition': competition.toMap(),
            'verificationStatus': 'none',
            'verifiedBadge': false,
            'verificationRequestId': '',
            'verificationReceiptId': '',
            'verificationPaymentId': '',
            'verificationProvider': '',
            'verificationRequestedAtMs': 0,
            'verificationApprovedAtMs': 0,
            'verificationExpiresAtMs': 0,
            'verificationReviewedBy': '',
            'verificationNote': '',
            'verificationRequestType': 'initial',
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
}
