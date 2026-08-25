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

  /// Keeps this user's search index entry in sync. Call after any write
  /// to UserProfile.teamName, shareId, avatar, or TeamProfile.game/badge.
  /// Best-effort — never throws to the caller.
  ///
  /// [country] is optional so existing call-sites that don't yet resolve
  /// a country keep compiling unchanged. When omitted, any existing
  /// `country` value already on the doc is left untouched (merge: true) —
  /// this call never clears a country that was previously set/backfilled.
  Future<void> syncSelfIndex({
    required String displayName,
    required String shareId,
    required String game,
    required String badge,
    required String avatarUrl,
    String? country,
  }) async {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    try {
      final payload = <String, dynamic>{
        'userId': uid,
        'displayName': displayName.trim(),
        'displayNameLower': displayName.trim().toLowerCase(),
        'shareId': shareId.trim(),
        'shareIdLower': shareId.trim().toLowerCase(), // Added for case-insensitive ID search
        'game': game.trim(),
        'badge': badge.trim(),
        'avatarUrl': avatarUrl.trim(),
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      };

      final trimmedCountry = (country ?? '').trim().toUpperCase();
      if (trimmedCountry.isNotEmpty) {
        payload['country'] = trimmedCountry;
      }

      await _col.doc(uid).set(payload, SetOptions(merge: true)).timeout(const Duration(seconds: 12));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[UserSearchRepository] syncSelfIndex failed (non-fatal): $e');
      }
    }
  }

  /// Convenience: reads the current UserProfile + TeamProfile for the
  /// signed-in user and re-syncs the index from both. Safe to call
  /// after any edit to either doc — avoids partial-field overwrites.
  Future<void> resyncSelfFromSources({
    required String displayName,
    required String shareId,
    required String avatarUrl,
    required String game,
    required String badge,
    String? country,
  }) => syncSelfIndex(
        displayName: displayName,
        shareId: shareId,
        game: game,
        badge: badge,
        avatarUrl: avatarUrl,
        country: country,
      );

  /// Background, best-effort backfill of the `country` field for the
  /// currently signed-in user's own search-index doc, IF it is missing.
  /// Safe to call repeatedly (no-ops once a country is set) — mirrors
  /// UserProfileRepository.ensureUsernameIfMissing()'s pattern so every
  /// existing user picks up "Teams Near You" eligibility the next time
  /// they simply open their own Profile tab, without needing to touch
  /// their team profile first. Never throws.
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

  /// "Teams Near You" — teams sharing the viewer's resolved country.
  /// Excludes the viewer themselves. Best-effort: returns an empty list
  /// on any failure rather than throwing, since this powers an
  /// auto-loading section that shouldn't block the rest of the screen.
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
          .limit(limit + 1) // +1 headroom in case self needs excluding
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

  /// Prefix search on display name (case-insensitive). Also tries an
  /// exact shareId match so users can search by their friend's Team ID.
  Future<List<UserSearchEntry>> search(String query, {int limit = 20}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final lower = trimmed.toLowerCase();

    try {
      final results = <String, UserSearchEntry>{};

      // 1. Prefix match on display name (case-insensitive).
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

      // 2. Exact shareId match (Team ID).
      if (trimmed.length >= 3) {
        // Try the new lowercase field first
        final idSnap = await _col
            .where('shareIdLower', isEqualTo: lower)
            .limit(5)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 12));

        for (final d in idSnap.docs) {
          final entry = UserSearchEntry.fromDoc(d);
          results[entry.userId] = entry;
        }

        // Fallback: Check the exact case-sensitive field for older profiles
        // that haven't been re-synced since the code update.
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
