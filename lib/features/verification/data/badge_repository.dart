// lib/features/verification/data/badge_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../domain/badge_model.dart';

/// Reads and writes badge state to Firestore.
///
/// Badges are stored as a nested map under the "verification" key
/// on the user document: users/{uid}
///
/// We use SetOptions(merge: true) on all writes so that no
/// existing user data is ever overwritten.
class BadgeRepository {
  BadgeRepository._();
  static final BadgeRepository instance = BadgeRepository._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Fetches the current badge state for [userId].
  /// Returns [VerificationBadges.empty] if the document or field
  /// does not exist.
  Future<VerificationBadges> fetchBadges(String userId) async {
    try {
      final doc = await _users
          .doc(userId)
          .get(const GetOptions(source: Source.serverAndCache));

      final data = doc.data();
      if (data == null) return VerificationBadges.empty;

      final raw = data['verification'];
      if (raw == null) return VerificationBadges.empty;
      if (raw is! Map) return VerificationBadges.empty;

      return VerificationBadges.fromMap(
          raw.cast<String, dynamic>());
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BadgeRepository] fetchBadges error: $e');
      }
      return VerificationBadges.empty;
    }
  }

  /// Streams the badge state for [userId].
  Stream<VerificationBadges> streamBadges(String userId) {
    return _users.doc(userId).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return VerificationBadges.empty;
      final raw = data['verification'];
      if (raw == null) return VerificationBadges.empty;
      if (raw is! Map) return VerificationBadges.empty;
      return VerificationBadges.fromMap(
          raw.cast<String, dynamic>());
    });
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Merges [badges] into the user document.
  /// Never overwrites unrelated fields.
  Future<void> saveBadges({
    required String userId,
    required VerificationBadges badges,
  }) async {
    final map = badges.toMap();
    // Remove null values so we don't accidentally null-out fields
    // that were previously set by another source.
    map.removeWhere((key, value) => value == null);

    await _users.doc(userId).set(
      {'verification': map},
      SetOptions(merge: true),
    );

    if (kDebugMode) {
      debugPrint(
        '[BadgeRepository] saveBadges for $userId: $map',
      );
    }
  }

  /// Atomically merges only the specified badge fields.
  /// Useful for granting a single badge without reading first.
  ///
  /// IMPORTANT: unlike [saveBadges], this method must NOT drop the
  /// `expiresAt` key when it is null. A badge transitioning from a
  /// subscription source (which has a future expiry) to a permanent
  /// source (manual_purchase / admin_granted, which must have NO
  /// expiry) needs the stale expiry timestamp explicitly cleared —
  /// otherwise the Firestore security rules' source/expiry pairing
  /// check (`_validSourceExpiry`) will reject the write, because the
  /// old expiry value would still be present alongside the new
  /// permanent source.
  Future<void> grantGreenBadge({
    required String userId,
    required BadgeSource source,
    DateTime? expiresAt,
  }) async {
    await _users
        .doc(userId)
        .set({'verification': {}}, SetOptions(merge: true));

    await _users.doc(userId).update(<String, dynamic>{
      'verification.greenVerified': true,
      'verification.greenSource': source.firestoreValue,
      'verification.greenExpiresAt':
          expiresAt != null ? Timestamp.fromDate(expiresAt) : null,
    });

    if (kDebugMode) {
      debugPrint(
        '[BadgeRepository] grantGreenBadge → $userId '
        'source=${source.firestoreValue} expiresAt=$expiresAt',
      );
    }
  }

  Future<void> grantOrganizerBadge({
    required String userId,
    required BadgeSource source,
    DateTime? expiresAt,
  }) async {
    await _users
        .doc(userId)
        .set({'verification': {}}, SetOptions(merge: true));

    await _users.doc(userId).update(<String, dynamic>{
      'verification.organizerVerified': true,
      'verification.organizerSource': source.firestoreValue,
      'verification.organizerExpiresAt':
          expiresAt != null ? Timestamp.fromDate(expiresAt) : null,
    });

    if (kDebugMode) {
      debugPrint(
        '[BadgeRepository] grantOrganizerBadge → $userId '
        'source=${source.firestoreValue} expiresAt=$expiresAt',
      );
    }
  }

  Future<void> grantStaffBadge({
    required String userId,
    required BadgeSource source,
    DateTime? expiresAt,
  }) async {
    await _users
        .doc(userId)
        .set({'verification': {}}, SetOptions(merge: true));

    await _users.doc(userId).update(<String, dynamic>{
      'verification.staffVerified': true,
      'verification.staffSource': source.firestoreValue,
      'verification.staffExpiresAt':
          expiresAt != null ? Timestamp.fromDate(expiresAt) : null,
    });

    if (kDebugMode) {
      debugPrint(
        '[BadgeRepository] grantStaffBadge → $userId '
        'source=${source.firestoreValue} expiresAt=$expiresAt',
      );
    }
  }

  /// Revokes a subscription-sourced green badge.
  /// If the user owns the badge via manual_purchase or admin_granted,
  /// this method is a no-op to preserve their permanent ownership.
  Future<void> revokeSubscriptionGreenBadge(
      String userId) async {
    final current = await fetchBadges(userId);
    if (!current.greenVerified) return;

    // Only revoke if the current source is subscription-based.
    final source = current.greenSource;
    if (source == BadgeSource.manualPurchase ||
        source == BadgeSource.adminGranted) {
      if (kDebugMode) {
        debugPrint(
          '[BadgeRepository] revokeSubscriptionGreenBadge skipped '
          'for $userId — source is $source (permanent).',
        );
      }
      return;
    }

    await _users.doc(userId).update({
      'verification.greenVerified': false,
      'verification.greenSource': null,
      'verification.greenExpiresAt': null,
    });

    if (kDebugMode) {
      debugPrint(
        '[BadgeRepository] revokeSubscriptionGreenBadge → $userId',
      );
    }
  }

  /// Revokes a subscription-sourced organizer badge.
  /// Preserves manual_purchase and admin_granted badges.
  Future<void> revokeSubscriptionOrganizerBadge(
      String userId) async {
    final current = await fetchBadges(userId);
    if (!current.organizerVerified) return;

    final source = current.organizerSource;
    if (source == BadgeSource.manualPurchase ||
        source == BadgeSource.adminGranted) {
      if (kDebugMode) {
        debugPrint(
          '[BadgeRepository] revokeSubscriptionOrganizerBadge skipped '
          'for $userId — source is $source (permanent).',
        );
      }
      return;
    }

    await _users.doc(userId).update({
      'verification.organizerVerified': false,
      'verification.organizerSource': null,
      'verification.organizerExpiresAt': null,
    });

    if (kDebugMode) {
      debugPrint(
        '[BadgeRepository] revokeSubscriptionOrganizerBadge '
        '→ $userId',
      );
    }
  }
}
