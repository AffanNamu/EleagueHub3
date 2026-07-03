// lib/features/verification/logic/badge_service.dart
import 'package:flutter/foundation.dart';
import '../data/badge_repository.dart';
import '../domain/badge_model.dart';

/// Subscription tier that drove a badge grant.
enum SubscriptionTier { pro, elite }

/// Central service that enforces all badge business rules.
///
/// Rules:
/// Pro → Green badge (expires when sub expires)
/// Elite → Green + Organizer badges (expire when sub expires)
/// Manual purchase → permanent (no expiry)
/// Admin granted → permanent (no expiry)
///
/// Elite overrides Pro.
/// Revocation preserves manual/admin-granted badges.
class BadgeService {
  BadgeService._();
  static final BadgeService instance = BadgeService._();
  final BadgeRepository _repo = BadgeRepository.instance;

  // ── Grant on subscription ─────────────────────────────────────────────────

  /// Called when a Pro subscription purchase succeeds.
  ///
  /// Grants Green badge with [expiresAt].
  /// Does NOT grant Organizer badge.
  Future<void> onProSubscriptionPurchased({
    required String userId,
    required DateTime expiresAt,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[BadgeService] onProSubscriptionPurchased '
        'userId=$userId expiresAt=$expiresAt',
      );
    }
    await _repo.grantGreenBadge(
      userId: userId,
      source: BadgeSource.proSubscription,
      expiresAt: expiresAt,
    );
  }

  /// Called when an Elite subscription purchase succeeds.
  ///
  /// Grants BOTH Green and Organizer badges with [expiresAt].
  /// Elite overrides Pro — if a Pro green badge already exists,
  /// the source is upgraded to elite_subscription.
  Future<void> onEliteSubscriptionPurchased({
    required String userId,
    required DateTime expiresAt,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[BadgeService] onEliteSubscriptionPurchased '
        'userId=$userId expiresAt=$expiresAt',
      );
    }
    // Grant green (upgrade source to elite if already pro).
    await _repo.grantGreenBadge(
      userId: userId,
      source: BadgeSource.eliteSubscription,
      expiresAt: expiresAt,
    );
    // Grant organizer — Elite users get this for free.
    await _repo.grantOrganizerBadge(
      userId: userId,
      source: BadgeSource.eliteSubscription,
      expiresAt: expiresAt,
    );
  }

  // ── Grant on manual purchase ──────────────────────────────────────────────

  /// Called when a user manually purchases Green Verification.
  ///
  /// Grants permanent Green badge (no expiry).
  /// Safe to call even if the user already owns it via subscription —
  /// upgrades the source to manual_purchase which is permanent.
  Future<void> onGreenVerificationPurchased({
    required String userId,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[BadgeService] onGreenVerificationPurchased '
        'userId=$userId',
      );
    }
    await _repo.grantGreenBadge(
      userId: userId,
      source: BadgeSource.manualPurchase,
      expiresAt: null, // permanent
    );
  }

  /// Called when a user manually purchases Organizer Verification.
  ///
  /// Grants permanent Organizer badge (no expiry).
  Future<void> onOrganizerVerificationPurchased({
    required String userId,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[BadgeService] onOrganizerVerificationPurchased '
        'userId=$userId',
      );
    }
    await _repo.grantOrganizerBadge(
      userId: userId,
      source: BadgeSource.manualPurchase,
      expiresAt: null, // permanent
    );
  }

  /// Called when a user renews Organizer Verification.
  ///
  /// Renewal extends the badge duration.
  /// [renewalDurationDays] defaults to 365 if not provided.
  Future<void> onOrganizerVerificationRenewalPurchased({
    required String userId,
    int renewalDurationDays = 365,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[BadgeService] onOrganizerVerificationRenewalPurchased '
        'userId=$userId days=$renewalDurationDays',
      );
    }
    final current = await _repo.fetchBadges(userId);
    // If currently subscription-sourced, treat renewal as
    // manual_purchase which makes it permanent.
    // If already manual, it stays manual (permanent, no expiry).
    final source = (current.organizerSource == BadgeSource.proSubscription ||
                    current.organizerSource == BadgeSource.eliteSubscription)
        ? BadgeSource.manualPurchase
        : BadgeSource.manualPurchase;
        
    await _repo.grantOrganizerBadge(
      userId: userId,
      source: source,
      expiresAt: null, // renewal always grants permanent ownership
    );
  }

  // ── Admin grant ───────────────────────────────────────────────────────────

  Future<void> adminGrantGreenBadge(String userId) async {
    await _repo.grantGreenBadge(
      userId: userId,
      source: BadgeSource.adminGranted,
      expiresAt: null,
    );
  }

  Future<void> adminGrantOrganizerBadge(String userId) async {
    await _repo.grantOrganizerBadge(
      userId: userId,
      source: BadgeSource.adminGranted,
      expiresAt: null,
    );
  }

  Future<void> adminGrantStaffBadge(String userId) async {
    await _repo.grantStaffBadge(
      userId: userId,
      source: BadgeSource.adminGranted,
      expiresAt: null,
    );
  }

  // ── Revoke on subscription expiry ────────────────────────────────────────

  /// Called when Pro subscription expires.
  ///
  /// Removes Green badge ONLY if it was granted by pro_subscription.
  /// Does NOT touch badges granted by elite_subscription,
  /// manual_purchase, or admin_granted.
  Future<void> onProSubscriptionExpired(String userId) async {
    if (kDebugMode) {
      debugPrint(
        '[BadgeService] onProSubscriptionExpired userId=$userId',
      );
    }
    final current = await _repo.fetchBadges(userId);
    // Only revoke if the green badge source is pro_subscription.
    if (current.greenSource == BadgeSource.proSubscription) {
      await _repo.revokeSubscriptionGreenBadge(userId);
    }
  }

  /// Called when Elite subscription expires.
  ///
  /// Removes BOTH Green and Organizer badges sourced from
  /// elite_subscription. Preserves manual/admin-granted badges.
  Future<void> onEliteSubscriptionExpired(String userId) async {
    if (kDebugMode) {
      debugPrint(
        '[BadgeService] onEliteSubscriptionExpired userId=$userId',
      );
    }
    final current = await _repo.fetchBadges(userId);
    if (current.greenSource == BadgeSource.eliteSubscription) {
      await _repo.revokeSubscriptionGreenBadge(userId);
    }
    if (current.organizerSource == BadgeSource.eliteSubscription) {
      await _repo.revokeSubscriptionOrganizerBadge(userId);
    }
  }

  // ── Read helpers ──────────────────────────────────────────────────────────

  Future<VerificationBadges> getBadges(String userId) => _repo.fetchBadges(userId);
  Stream<VerificationBadges> streamBadges(String userId) => _repo.streamBadges(userId);

  /// Determines whether the purchase button for a product should
  /// be disabled because the subscription already includes it.
  ///
  /// Returns a non-null string (the label to show) if disabled,
  /// or null if the button should be active.
  String? purchaseBlockedReason({
    required VerificationBadges badges,
    required bool isGreenProduct,
    required bool isOrganizerProduct,
  }) {
    if (isGreenProduct) {
      if (badges.greenSource == BadgeSource.eliteSubscription && badges.isGreenActive) {
        return 'Included with your Elite subscription';
      }
      if (badges.greenSource == BadgeSource.proSubscription && badges.isGreenActive) {
        return 'Included with your Pro subscription';
      }
    }
    if (isOrganizerProduct) {
      if (badges.organizerSource == BadgeSource.eliteSubscription && badges.isOrganizerActive) {
        return 'Included with your Elite subscription';
      }
    }
    return null;
  }
}
