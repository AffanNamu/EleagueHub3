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

    throw const UserFriendlyException('Something went wrong. Please try again.');
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

  Future<void> checkLeagueLimitOrThrow(String masterLeagueId) async {
    final ml = await getById(masterLeagueId);
    if (ml == null) {
      throw const UserFriendlyException("We couldn't find that Master League.");
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
        throw const UserFriendlyException('Invalid short id. Example: eS44e35f');
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

  Stream<List<CompetitionTemplate>> watchCompetitionTemplates(
      String masterLeagueId) {
    try {
      _requireAuthUid();
      final id = masterLeagueId.trim();
      if (id.isEmpty) return const Stream<List<CompetitionTemplate>>.empty();

      return _templatesCol(id)
          .orderBy('updatedAtMs', descending: true)
          .snapshots(includeMetadataChanges: true)
          .map((snap) {
        return snap.docs
            .map((d) => CompetitionTemplate.fromMap(d.data()))
            .toList(growable: false);
      });
    } catch (_) {
      return const Stream<List<CompetitionTemplate>>.empty();
    }
  }

  Stream<bool> watchIsFollowing(String masterLeagueId) {
    try {
      final uid = _requireAuthUid();
      final id = masterLeagueId.trim();
      if (id.isEmpty) return Stream<bool>.value(false);
      return _followersCol(id).doc(uid).snapshots().map((snap) => snap.exists);
    } catch (_) {
      return const Stream<bool>.empty();
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
      return const Stream<int>.empty();
    }
  }
}
