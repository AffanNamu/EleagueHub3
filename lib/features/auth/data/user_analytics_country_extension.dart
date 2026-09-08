// lib/features/auth/data/user_analytics_country_extension.dart
//
// Adds one method to the user-profile write path: a one-time,
// best-effort backfill of users/{uid}.analyticsCountry, following the
// exact same defensive pattern as UserSearchRepository.backfillCountryIfMissing()
// (self-heal only if missing, best-effort, never fatal, never overwrites
// an existing value). Kept as a small standalone extension rather than
// edited directly into user_profile_repository.dart so the diff against
// that file stays minimal and easy to review.
//
// CALL SITE: wire this into whatever runs backfillCountryIfMissing() and
// backfillDisplayNameIfMissing() today — likely auth_bootstrap.dart or
// app_startup_service.dart. Confirm the exact call site before wiring;
// it should run once per session, same cadence as the other backfills.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/services/country/country_analytics_service.dart';

class UserAnalyticsCountryBackfill {
  UserAnalyticsCountryBackfill({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Future<void> backfillIfMissing() async {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return;

    try {
      final ref = _firestore.collection('users').doc(uid);
      final doc = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      final existing = (doc.data()?['analyticsCountry'] as String? ?? '').trim();
      if (existing.isNotEmpty) return;

      final resolved = await CountryAnalyticsService.instance.resolveCountryCodeForAnalytics();
      if (resolved.isEmpty) {
        // Genuinely unknown — do not write a guessed value, and do not
        // write an empty string either (leave the field entirely absent
        // so it's distinguishable from "we checked and found nothing").
        return;
      }

      await ref.set(
        <String, dynamic>{
          'userId': uid,
          'analyticsCountry': resolved,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 12));

      if (kDebugMode) {
        debugPrint('[UserAnalyticsCountryBackfill] set analyticsCountry=$resolved for $uid');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[UserAnalyticsCountryBackfill] failed (non-fatal): $e');
      }
    }
  }
}
