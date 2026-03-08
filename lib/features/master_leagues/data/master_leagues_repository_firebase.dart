import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/master_league.dart';
import '../domain/master_league_plan.dart';

/// User-safe exception: if UI shows `$e`, it will still be a friendly message.
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

  String _requireAuthUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const UserFriendlyException('Please sign in and try again.');
    }
    return uid;
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

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
      debugPrint(
        '[MasterLeaguesRepo] FirebaseException code=${error.code} '
        'message=${error.message}',
      );
      switch (error.code) {
        case 'unavailable':
        case 'deadline-exceeded':
          throw const UserFriendlyException(
            'Your network appears to be offline. Please check your connection and try again.',
          );
        case 'permission-denied':
          throw const UserFriendlyException(
            'You don\'t have access to this Master League. '
            'Please make sure your subscription is active and try again.',
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

  /// Watches Master Leagues where the current user is a member.
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
          if (at == null && bt == null) return b.id.compareTo(a.id);
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

  /// Creates a new Master League with a plan tier.
  ///
  /// Retries up to 3 times with delays if permission-denied occurs,
  /// because the entitlement doc may not yet be visible to Firestore
  /// rules immediately after writing it in a transaction.
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

      final id = _uuid.v4();
      final ref = _col.doc(id);
      final now = _nowMs();

      final docData = <String, dynamic>{
        'name': trimmed,
        'ownerId': uid,
        'createdAt': Timestamp.now(),
        'purchaseStatus': 'active',
        'memberIds': <String>[uid],
        'updatedAtMs': now,
        'plan': plan.id,
      };

      debugPrint(
        '[MasterLeaguesRepo] Creating: name="$trimmed" uid=$uid id=$id plan=${plan.id}',
      );

      // Retry logic: entitlement doc may not be immediately visible
      // to Firestore rules after being written in a transaction.
      const maxRetries = 3;
      const retryDelays = [
        Duration(seconds: 2),
        Duration(seconds: 3),
        Duration(seconds: 4),
      ];

      for (int attempt = 0; attempt < maxRetries; attempt++) {
        try {
          await ref
              .set(docData, SetOptions(merge: false))
              .timeout(const Duration(seconds: 20));

          debugPrint('[MasterLeaguesRepo] Created successfully: $id (attempt ${attempt + 1})');

          // Read back the created document
          final fresh = await ref
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 15));
          return MasterLeague.fromDoc(fresh);
        } on FirebaseException catch (e) {
          if (e.code == 'permission-denied' && attempt < maxRetries - 1) {
            debugPrint(
              '[MasterLeaguesRepo] Permission denied on attempt ${attempt + 1}, '
              'retrying in ${retryDelays[attempt].inSeconds}s...',
            );
            await Future<void>.delayed(retryDelays[attempt]);
            // Regenerate timestamp for retry
            docData['createdAt'] = Timestamp.now();
            docData['updatedAtMs'] = _nowMs();
            continue;
          }
          rethrow;
        }
      }

      // Should not reach here, but just in case
      throw const UserFriendlyException(
        'Could not create Master League. Please try again.',
      );
    } catch (e) {
      debugPrint('[MasterLeaguesRepo] Create failed: $e');
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Basic ownership check.
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
          (data['ownerId'] as String? ?? data['ownerUid'] as String? ?? '')
              .trim();

      if (ownerId.isEmpty || ownerId != uid) {
        throw const UserFriendlyException(
          'Only the Master League owner can perform this action.',
        );
      }
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Checks if the master league can accept more competitions.
  Future<void> checkLeagueLimitOrThrow(String masterLeagueId) async {
    final ml = await getById(masterLeagueId);
    if (ml == null) {
      throw const UserFriendlyException(
        "We couldn't find that Master League.",
      );
    }

    final maxLeagues = ml.maxLeagues;

    // Count existing leagues under this master league
    final snap = await _firestore
        .collection('leagues')
        .where('masterLeagueId', isEqualTo: masterLeagueId.trim())
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));

    final count = snap.docs.length;

    if (count >= maxLeagues) {
      throw UserFriendlyException(
        'You have reached the limit of $maxLeagues competitions '
        'for your ${ml.plan.displayName} plan. '
        'Upgrade your plan to create more.',
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

      await _col
          .doc(masterLeagueId.trim())
          .update(<String, dynamic>{
            'name': name,
            'updatedAtMs': _nowMs(),
          })
          .timeout(const Duration(seconds: 12));
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

      await _col
          .doc(masterLeagueId.trim())
          .update(<String, dynamic>{
            'memberIds': FieldValue.arrayUnion([m]),
            'updatedAtMs': _nowMs(),
          })
          .timeout(const Duration(seconds: 12));
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

      await _col
          .doc(masterLeagueId.trim())
          .update(<String, dynamic>{
            'memberIds': FieldValue.arrayRemove([m]),
            'updatedAtMs': _nowMs(),
          })
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Deletes a Master League (owner only).
  Future<void> delete(String masterLeagueId) async {
    try {
      await requireOwnerOrThrow(masterLeagueId);

      final id = masterLeagueId.trim();

      // Best-effort: unlink child leagues
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
          debugPrint(
            '[MasterLeaguesRepo] Unlinked ${childLeagues.docs.length} child leagues',
          );
        }
      } catch (e) {
        debugPrint(
          '[MasterLeaguesRepo] Failed to unlink child leagues: $e',
        );
      }

      await _col.doc(id).delete().timeout(const Duration(seconds: 15));
      debugPrint('[MasterLeaguesRepo] Deleted master league: $id');
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }
}
