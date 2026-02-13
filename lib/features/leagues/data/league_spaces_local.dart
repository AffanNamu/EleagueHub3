import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/services/connectivity_service.dart';
import '../../../core/persistence/prefs_service.dart';
import '../models/league_space.dart';

/// User-safe exception: if UI shows `$e`, it will still be a friendly message.
class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

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
  // Online-only: prefs must not be used for domain storage.
  // ignore: unused_field
  final PreferencesService _prefs;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String leagueId) {
    return _firestore.collection('leagues').doc(leagueId).collection('space').doc('current');
  }

  String _requireAuthUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      throw const UserFriendlyException('Please sign in and try again.');
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
    try {
      _requireAuthUid();
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final snap = await _doc(leagueId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      if (!snap.exists) return null;

      final data = snap.data();
      if (data == null) return null;

      return _tryParse(data);
    } catch (_) {
      // Online-only: if we can't load, return null and let UI handle empty state.
      return null;
    }
  }

  Stream<LeagueSpace?> watchSpace(String leagueId) {
    final src = _doc(leagueId).snapshots(includeMetadataChanges: true);

    return src.transform(
      StreamTransformer<DocumentSnapshot<Map<String, dynamic>>, LeagueSpace?>.fromHandlers(
        handleData: (snap, sink) {
          // Online-only: ignore cache snapshots.
          if (snap.metadata.isFromCache) return;

          final data = snap.data();
          if (!snap.exists || data == null) {
            sink.add(null);
            return;
          }
          sink.add(_tryParse(data));
        },
        handleError: (error, stack, sink) {
          // Do not leak stream errors; emit null.
          sink.add(null);
        },
      ),
    );
  }

  Future<LeagueSpace> startSpace({
    required String leagueId,
    required String hostUserId,
    required String title,
  }) async {
    try {
      final uid = _requireAuthUid();
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      if (hostUserId.trim().isEmpty) {
        throw const UserFriendlyException('Please try again.');
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
    } catch (e) {
      if (e is UserFriendlyException) rethrow;
      throw const UserFriendlyException("We couldn't start the space right now. Please try again.");
    }
  }

  Future<LeagueSpace> endSpace(String leagueId) async {
    try {
      _requireAuthUid();
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

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
    } catch (e) {
      if (e is UserFriendlyException) rethrow;
      throw const UserFriendlyException("We couldn't end the space right now. Please try again.");
    }
  }
}
