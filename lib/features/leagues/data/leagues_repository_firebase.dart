import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/league.dart';
import '../models/membership.dart';

/// User-safe exception: if UI shows `$e`, it will still be a friendly message.
class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

class LeaguesRepositoryFirebase {
  LeaguesRepositoryFirebase({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

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

      final base = _leaguesCol.where('memberIds', arrayContains: uid).snapshots(includeMetadataChanges: true);

      final serverOnly = base.where((snap) => !snap.metadata.isFromCache).map(
            (snapshot) => snapshot.docs.map(_docToLeague).toList(growable: false),
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

      final doc = await _leaguesCol.doc(id).get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));

      if (!doc.exists) return null;
      return _snapToLeague(doc);
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Ensures:
  /// - organizerUid/ownerUid = auth uid
  /// - memberIds contains auth uid
  /// - memberships/{authUid} exists (needed by membership-based rules, chatroom)
  ///
  /// SECURITY NOTE:
  /// - In production, pair this with Firestore Security Rules enforcing:
  ///   - Only league admins can modify admin-only fields
  ///   - Admin Point Adjustment writes go to pointAdjustments and aggregate fields
  ///   - Prevent direct finalPoints overwrite unless invariant holds
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

      final leagueRef = _leaguesCol.doc(id);
      final membershipRef = leagueRef.collection('memberships').doc(authUid);

      final now = DateTime.now().millisecondsSinceEpoch;

      final batch = _firestore.batch();

      batch.set(
        leagueRef,
        {
          ...fixed.toJson(),
          'organizerUid': authUid,
          'ownerUid': authUid,
          'ownerId': authUid,
          'memberIds': FieldValue.arrayUnion([authUid]),
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      );

      final membership = Membership(
        id: authUid,
        leagueId: id,
        userId: authUid,
        teamId: null,
        role: LeagueRole.organizer,
        updatedAtMs: now,
        version: 1,
      );

      batch.set(membershipRef, membership.toRemoteMap(), SetOptions(merge: true));

      await batch.commit().timeout(const Duration(seconds: 25));
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
