//lib/features/search/data/user_search_repository.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/services/country/country_resolver_service.dart';
import '../models/user_search_entry.dart';

class UserSearchRepository {
  UserSearchRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('user_search');

  Future<void> syncSelfIndex({
    required String displayName,
    required String shareId,
    required String game,
    required String badge,
    required String avatarUrl,
    String? country,
    String? usernameLower,
  }) async {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    try {
      final payload = <String, dynamic>{
        'userId': uid,
        'displayName': displayName.trim(),
        'displayNameLower': displayName.trim().toLowerCase(),
        'shareId': shareId.trim(),
        'shareIdLower': shareId.trim().toLowerCase(),
        'game': game.trim(),
        'badge': badge.trim(),
        'avatarUrl': avatarUrl.trim(),
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      };

      final trimmedCountry = (country ?? '').trim().toUpperCase();
      if (trimmedCountry.isNotEmpty) {
        payload['country'] = trimmedCountry;
      }

      final trimmedUsername = (usernameLower ?? '').trim().toLowerCase();
      if (trimmedUsername.isNotEmpty) {
        payload['usernameLower'] = trimmedUsername;
      }

      await _col.doc(uid).set(payload, SetOptions(merge: true)).timeout(const Duration(seconds: 12));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[UserSearchRepository] syncSelfIndex failed (non-fatal): $e');
      }
    }
  }

  Future<void> resyncSelfFromSources({
    required String displayName,
    required String shareId,
    required String avatarUrl,
    required String game,
    required String badge,
    String? country,
    String? usernameLower,
  }) => syncSelfIndex(
        displayName: displayName,
        shareId: shareId,
        game: game,
        badge: badge,
        avatarUrl: avatarUrl,
        country: country,
        usernameLower: usernameLower,
      );

  /// Best-effort, called immediately after UserProfileRepository commits
  /// a username reservation (both manual edit and auto-assignment), so
  /// the search index stays in sync without every caller having to know
  /// about it. Writes ONLY userId/usernameLower/updatedAtMs — never
  /// throws.
  Future<void> syncUsername(String usernameLower) async {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    final lower = usernameLower.trim().toLowerCase();
    if (uid.isEmpty || lower.isEmpty) return;

    try {
      await _col.doc(uid).set(
        <String, dynamic>{
          'userId': uid,
          'usernameLower': lower,
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 12));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[UserSearchRepository] syncUsername failed (non-fatal): $e');
      }
    }
  }

  Future<void> backfillCountryIfMissing() async {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    try {
      final doc = await _col
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      final existing = (doc.data()?['country'] as String? ?? '').trim();
      if (existing.isNotEmpty) return;

      final resolved = await CountryResolverService.instance.resolveCountryCode();
      final trimmed = resolved.trim().toUpperCase();
      if (trimmed.isEmpty) return;

      await _col.doc(uid).set(
        <String, dynamic>{
          'userId': uid,
          'country': trimmed,
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 12));

      if (kDebugMode) {
        debugPrint('[UserSearchRepository] backfillCountryIfMissing: set country=$trimmed for $uid');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[UserSearchRepository] backfillCountryIfMissing failed (non-fatal): $e');
      }
    }
  }

  Future<List<UserSearchEntry>> fetchNearby({
    required String countryCode,
    int limit = 20,
  }) async {
    final cc = countryCode.trim().toUpperCase();
    if (cc.isEmpty) return const [];

    final selfUid = _auth.currentUser?.uid.trim() ?? '';

    try {
      final snap = await _col
          .where('country', isEqualTo: cc)
          .orderBy('updatedAtMs', descending: true)
          .limit(limit + 1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      final out = <UserSearchEntry>[];
      for (final d in snap.docs) {
        if (d.id == selfUid) continue;
        out.add(UserSearchEntry.fromDoc(d));
        if (out.length >= limit) break;
      }
      return out;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[UserSearchRepository] fetchNearby failed: $e');
      }
      return const [];
    }
  }

  Future<List<UserSearchEntry>> search(String query, {int limit = 20}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    var lower = trimmed.toLowerCase();
    if (lower.startsWith('@')) lower = lower.substring(1);

    try {
      final results = <String, UserSearchEntry>{};

      final nameSnap = await _col
          .orderBy('displayNameLower')
          .startAt([lower])
          .endAt(['$lower\uf8ff'])
          .limit(limit)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      for (final d in nameSnap.docs) {
        final entry = UserSearchEntry.fromDoc(d);
        results[entry.userId] = entry;
      }

      // Exact username match — trigger for @-prefixed queries or once
      // enough characters have been typed that it's plausibly a username.
      if (trimmed.startsWith('@') || lower.length >= 3) {
        try {
          final usernameSnap = await _col
              .where('usernameLower', isEqualTo: lower)
              .limit(5)
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 12));

          for (final d in usernameSnap.docs) {
            final entry = UserSearchEntry.fromDoc(d);
            results[entry.userId] = entry;
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[UserSearchRepository] username search failed: $e');
          }
        }
      }

      if (trimmed.length >= 3) {
        final idSnap = await _col
            .where('shareIdLower', isEqualTo: lower)
            .limit(5)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 12));

        for (final d in idSnap.docs) {
          final entry = UserSearchEntry.fromDoc(d);
          results[entry.userId] = entry;
        }

        if (results.isEmpty) {
          final idSnapExact = await _col
              .where('shareId', isEqualTo: trimmed)
              .limit(5)
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 12));

          for (final d in idSnapExact.docs) {
            final entry = UserSearchEntry.fromDoc(d);
            results[entry.userId] = entry;
          }
        }
      }

      return results.values.toList(growable: false);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[UserSearchRepository] search failed: $e');
      }
      return const [];
    }
  }
}
