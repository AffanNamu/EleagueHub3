// lib/core/services/payments/google_play_billing_catalog.dart

import '../../../features/master_leagues/domain/master_league_plan.dart';

class GooglePlayBillingCatalog {
  const GooglePlayBillingCatalog._();

  // ── Subscriptions for organizer plans ─────────────────────────────────────

  static const String pro3MonthsSubscriptionId =
      String.fromEnvironment(
    'GPB_SUB_PRO_3MO_ID',
    defaultValue: 'pro_3mo',
  );

  static const String pro6MonthsSubscriptionId =
      String.fromEnvironment(
    'GPB_SUB_PRO_6MO_ID',
    defaultValue: 'pro_6mo',
  );

  static const String proYearlySubscriptionId =
      String.fromEnvironment(
    'GPB_SUB_PRO_YEARLY_ID',
    defaultValue: 'pro_yearly',
  );

  static const String elite3MonthsSubscriptionId =
      String.fromEnvironment(
    'GPB_SUB_ELITE_3MO_ID',
    defaultValue: 'elite_3mo',
  );

  static const String elite6MonthsSubscriptionId =
      String.fromEnvironment(
    'GPB_SUB_ELITE_6MO_ID',
    defaultValue: 'elite_6mo',
  );

  static const String eliteYearlySubscriptionId =
      String.fromEnvironment(
    'GPB_SUB_ELITE_YEARLY_ID',
    defaultValue: 'elite_yearly',
  );

  // ── One-time / consumable products ────────────────────────────────────────

  static const String leagueCreationUnlockId =
      String.fromEnvironment(
    'GPB_LEAGUE_CREATION_UNLOCK_ID',
    defaultValue: 'league_creation_unlock',
  );

  static const String leagueAddonsPackId = String.fromEnvironment(
    'GPB_LEAGUE_ADDONS_PACK_ID',
    defaultValue: 'league_addons_pack',
  );

  static const String leagueAccessUnlockId =
      String.fromEnvironment(
    'GPB_LEAGUE_ACCESS_UNLOCK_ID',
    defaultValue: 'league_access_unlock',
  );

  static const String organizerVerificationId =
      String.fromEnvironment(
    'GPB_ORGANIZER_VERIFICATION_ID',
    defaultValue: 'organizer_verification',
  );

  static const String organizerVerificationRenewalId =
      String.fromEnvironment(
    'GPB_ORGANIZER_VERIFICATION_RENEWAL_ID',
    defaultValue: 'organizer_verification_renewal',
  );

  // ── Premium app subscription ──────────────────────────────────────────────

  static const String premiumSubscriptionId =
      String.fromEnvironment(
    'GPB_PREMIUM_SUB_ID',
    defaultValue: 'premium_subscription',
  );

  // ── Existing helpers (unchanged) ──────────────────────────────────────────

  static String subscriptionIdForPlan({
    required MasterLeaguePlan plan,
    required PlanDuration duration,
  }) {
    switch (plan) {
      case MasterLeaguePlan.pro:
        switch (duration) {
          case PlanDuration.threeMonths:
            return pro3MonthsSubscriptionId;
          case PlanDuration.sixMonths:
            return pro6MonthsSubscriptionId;
          case PlanDuration.yearly:
            return proYearlySubscriptionId;
        }
      case MasterLeaguePlan.elite:
        switch (duration) {
          case PlanDuration.threeMonths:
            return elite3MonthsSubscriptionId;
          case PlanDuration.sixMonths:
            return elite6MonthsSubscriptionId;
          case PlanDuration.yearly:
            return eliteYearlySubscriptionId;
        }
      case MasterLeaguePlan.basic:
        return '';
    }
  }

  static Map<String, String> allProductIds() {
    return <String, String>{
      'pro_3mo': pro3MonthsSubscriptionId,
      'pro_6mo': pro6MonthsSubscriptionId,
      'pro_yearly': proYearlySubscriptionId,
      'elite_3mo': elite3MonthsSubscriptionId,
      'elite_6mo': elite6MonthsSubscriptionId,
      'elite_yearly': eliteYearlySubscriptionId,
      'league_creation_unlock': leagueCreationUnlockId,
      'league_addons_pack': leagueAddonsPackId,
      'league_access_unlock': leagueAccessUnlockId,
      'organizer_verification': organizerVerificationId,
      'organizer_verification_renewal':
          organizerVerificationRenewalId,
      'premium_subscription': premiumSubscriptionId,
    };
  }

  // ── NEW: Badge tier helpers ───────────────────────────────────────────────

  /// Returns badge tier information for a given [productId].
  ///
  /// Returns null if the product is not a plan subscription
  /// (e.g. it is a one-time product or an unrelated subscription).
  ///
  /// Used exclusively by [GooglePlayBillingService._grantBadgesForProduct]
  /// to decide which badges to grant without hardcoding tier logic
  /// in multiple places.
  static _SubscriptionTierInfo? tierInfoForProductId(
      String productId) {
    // Pro — 3 months
    if (productId == pro3MonthsSubscriptionId) {
      return const _SubscriptionTierInfo(
        tier: PlanSubscriptionTier.pro,
        durationDays: 90,
      );
    }
    // Pro — 6 months
    if (productId == pro6MonthsSubscriptionId) {
      return const _SubscriptionTierInfo(
        tier: PlanSubscriptionTier.pro,
        durationDays: 180,
      );
    }
    // Pro — yearly
    if (productId == proYearlySubscriptionId) {
      return const _SubscriptionTierInfo(
        tier: PlanSubscriptionTier.pro,
        durationDays: 365,
      );
    }
    // Elite — 3 months
    if (productId == elite3MonthsSubscriptionId) {
      return const _SubscriptionTierInfo(
        tier: PlanSubscriptionTier.elite,
        durationDays: 90,
      );
    }
    // Elite — 6 months
    if (productId == elite6MonthsSubscriptionId) {
      return const _SubscriptionTierInfo(
        tier: PlanSubscriptionTier.elite,
        durationDays: 180,
      );
    }
    // Elite — yearly
    if (productId == eliteYearlySubscriptionId) {
      return const _SubscriptionTierInfo(
        tier: PlanSubscriptionTier.elite,
        durationDays: 365,
      );
    }

    return null;
  }

  /// Returns true if [productId] resolves to a Pro-tier subscription.
  static bool isProSubscription(String productId) {
    return productId == pro3MonthsSubscriptionId ||
        productId == pro6MonthsSubscriptionId ||
        productId == proYearlySubscriptionId;
  }

  /// Returns true if [productId] resolves to an Elite-tier subscription.
  static bool isEliteSubscription(String productId) {
    return productId == elite3MonthsSubscriptionId ||
        productId == elite6MonthsSubscriptionId ||
        productId == eliteYearlySubscriptionId;
  }

  /// Returns true if [productId] is the organizer_verification or
  /// organizer_verification_renewal one-time product.
  static bool isOrganizerVerificationProduct(String productId) {
    return productId == organizerVerificationId ||
        productId == organizerVerificationRenewalId;
  }
}

// ── Internal types ────────────────────────────────────────────────────────────

/// Which plan tier a subscription belongs to.
enum PlanSubscriptionTier { pro, elite }

/// Tier + duration information returned by [tierInfoForProductId].
class _SubscriptionTierInfo {
  final PlanSubscriptionTier tier;
  final int durationDays;

  const _SubscriptionTierInfo({
    required this.tier,
    required this.durationDays,
  });
}