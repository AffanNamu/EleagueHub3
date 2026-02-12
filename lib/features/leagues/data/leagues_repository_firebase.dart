import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/league.dart';

/// User-safe exception: if UI shows `$e`, it will still be a friendly message.
class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

class LeaguesRepositoryFirebase {
  LeaguesRepositoryFirebase({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Uuid _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> get _leaguesCol => _firestore.collection('leagues');

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
      throw const UserFriendlyException('Your internet connection seems unstable. Please try again.');
    }

    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
        case 'deadline-exceeded':
          throw const UserFriendlyException(
            'Your network appears to be offline. Please check your connection and try again.',
          );
        case 'permission-denied':
          throw const UserFriendlyException('You don’t have access to this league.');
        case 'unauthenticated':
          throw const UserFriendlyException('Please sign in and try again.');
        default:
          throw const UserFriendlyException("We couldn't complete this action. Please try again.");
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

  /// ONLINE-ONLY:
  /// Fetches ONLY leagues the current user is a member of (avoids permission errors and huge reads).
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

  /// ONLINE-ONLY STREAM POLICY:
  /// Firestore snapshots can produce cached events (even with disk persistence disabled).
  /// To avoid showing stale/offline data, we:
  /// - enable metadata changes
  /// - ignore any snapshot where `metadata.isFromCache == true`
  ///
  /// If the device is offline, no server snapshots will arrive; UI should show offline UX.
  Stream<List<League>> watchLeagues() {
    try {
      final uid = _requireAuthUid();

      final base = _leaguesCol
          .where('memberIds', arrayContains: uid)
          .snapshots(includeMetadataChanges: true);

      final serverOnly = base.where((snap) => !snap.metadata.isFromCache).map(
            (snapshot) => snapshot.docs.map(_docToLeague).toList(growable: false),
          );

      // Never emit raw errors to UI.
      return serverOnly.handleError((error, stack) {
        if (kDebugMode) {
          debugPrint('LeaguesRepositoryFirebase.watchLeagues error: $error');
        }
      });
    } catch (_) {
      // If not signed in, router should have redirected already. Fail gracefully.
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

  /// IMPORTANT:
  /// - Rules authority is FirebaseAuth UID only.
  /// - This method always writes organizerUid/ownerUid = request.auth.uid.
  /// - Ensures memberIds contains request.auth.uid.
  Future<void> saveLeague(League league) async {
    try {
      final authUid = _requireAuthUid();

      final id = league.id.trim().isEmpty ? _uuid.v4() : league.id.trim();

      final fixed = league.copyWith(
        id: id,
        organizerUid: authUid,
        code: league.code.trim().toUpperCase(),
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      await _leaguesCol
          .doc(id)
          .set(
            {
              ...fixed.toJson(),

              // Rules-authoritative owner fields
              'organizerUid': authUid,
              'ownerUid': authUid,

              // Back-compat but must be Firebase UID if present
              'ownerId': authUid,

              // Membership must contain ONLY Firebase UIDs.
              'memberIds': FieldValue.arrayUnion([authUid]),
            },
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> deleteLeague(String leagueId) async {
    try {
      _requireAuthUid();
      await _leaguesCol.doc(leagueId).delete().timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }
}
