import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;

import '../../../core/persistence/prefs_service.dart';
import '../models/league_space.dart';

/// ONLINE-ONLY Firestore implementation (legacy file name kept for compatibility).
///
/// This project previously had "local" space handling + sync. Online-only rules:
/// - No local persistence
/// - No background sync
/// - All space state is live in Firestore
///
/// Collection layout:
/// leagues/{leagueId}/space/current
class LeagueSpacesFirebase {
  LeagueSpacesFirebase(this._prefs);

  // Kept only to avoid breaking constructors across the codebase.
  // ignore: unused_field
  final PreferencesService _prefs;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String leagueId) {
    return _firestore.collection('leagues').doc(leagueId).collection('space').doc('current');
  }

  String _requireAuthUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const FirebaseAuthException(code: 'unauthenticated');
    }
    return uid;
  }

  LeagueSpace? _tryParse(Map<String, dynamic> data) {
    try {
      return LeagueSpace.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// Returns current space doc (live). Returns null if missing or not parseable.
  Future<LeagueSpace?> getSpace(String leagueId) async {
    return getActiveSpace(leagueId);
  }

  Future<LeagueSpace?> getActiveSpace(String leagueId) async {
    final snap = await _doc(leagueId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));

    if (!snap.exists) return null;

    final data = snap.data();
    if (data == null) return null;

    return _tryParse(data);
  }

  Stream<LeagueSpace?> watchSpace(String leagueId) {
    return _doc(leagueId).snapshots().map((snap) {
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return _tryParse(data);
    }).handleError((_) {
      // Suppress raw stream errors at UI level; callers should show friendly state.
    });
  }

  Future<LeagueSpace> startSpace({
    required String leagueId,
    required String hostUserId,
    required String title,
  }) async {
    final uid = _requireAuthUid();

    if (hostUserId.trim().isEmpty) {
      throw const FirebaseException(plugin: 'cloud_firestore', code: 'invalid-argument');
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    await _doc(leagueId)
        .set(
          {
            'leagueId': leagueId,
            'hostUserId': hostUserId.trim(),
            'hostUid': uid, // explicit auth uid for rules/debug
            'title': title.trim(),
            'isLive': true,
            'startedAtMs': now,
            'updatedAtMs': now,
          },
          SetOptions(merge: true),
        )
        .timeout(const Duration(seconds: 15));

    final snap = await _doc(leagueId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));

    final data = snap.data();
    final parsed = data == null ? null : _tryParse(data);
    if (parsed == null) {
      // Fallback: create a minimal object from the just-written payload if parsing failed.
      return LeagueSpace.fromJson({
        'leagueId': leagueId,
        'hostUserId': hostUserId.trim(),
        'title': title.trim(),
        'isLive': true,
        'startedAtMs': now,
        'updatedAtMs': now,
      });
    }

    return parsed;
  }

  Future<LeagueSpace> endSpace(String leagueId) async {
    _requireAuthUid();

    final now = DateTime.now().millisecondsSinceEpoch;

    await _doc(leagueId)
        .set(
          {
            'isLive': false,
            'endedAtMs': now,
            'updatedAtMs': now,
          },
          SetOptions(merge: true),
        )
        .timeout(const Duration(seconds: 15));

    final snap = await _doc(leagueId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));

    final data = snap.data();
    final parsed = data == null ? null : _tryParse(data);
    if (parsed == null) {
      return LeagueSpace.fromJson({
        'leagueId': leagueId,
        'isLive': false,
        'endedAtMs': now,
        'updatedAtMs': now,
      });
    }

    return parsed;
  }
}
