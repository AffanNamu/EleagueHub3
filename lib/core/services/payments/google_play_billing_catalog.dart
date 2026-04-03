import '../../../features/master_leagues/domain/master_league_plan.dart';

class GooglePlayBillingCatalog {
  const GooglePlayBillingCatalog._();

  // Subscriptions for organizer plans
  static const String pro3MonthsSubscriptionId = String.fromEnvironment(
    'GPB_SUB_PRO_3MO_ID',
    defaultValue: 'pro_3mo',
  );

  static const String pro6MonthsSubscriptionId = String.fromEnvironment(
    'GPB_SUB_PRO_6MO_ID',
    defaultValue: 'pro_6mo',
  );

  static const String proYearlySubscriptionId = String.fromEnvironment(
    'GPB_SUB_PRO_YEARLY_ID',
    defaultValue: 'pro_yearly',
  );

  static const String elite3MonthsSubscriptionId = String.fromEnvironment(
    'GPB_SUB_ELITE_3MO_ID',
    defaultValue: 'elite_3mo',
  );

  static const String elite6MonthsSubscriptionId = String.fromEnvironment(
    'GPB_SUB_ELITE_6MO_ID',
    defaultValue: 'elite_6mo',
  );

  static const String eliteYearlySubscriptionId = String.fromEnvironment(
    'GPB_SUB_ELITE_YEARLY_ID',
    defaultValue: 'elite_yearly',
  );

  // One-time / consumable scaffolds
  static const String leagueCreationUnlockId = String.fromEnvironment(
    'GPB_LEAGUE_CREATION_UNLOCK_ID',
    defaultValue: 'league_creation_unlock',
  );

  static const String leagueAddonsPackId = String.fromEnvironment(
    'GPB_LEAGUE_ADDONS_PACK_ID',
    defaultValue: 'league_addons_pack',
  );

  static const String leagueAccessUnlockId = String.fromEnvironment(
    'GPB_LEAGUE_ACCESS_UNLOCK_ID',
    defaultValue: 'league_access_unlock',
  );

  static const String organizerVerificationId = String.fromEnvironment(
    'GPB_ORGANIZER_VERIFICATION_ID',
    defaultValue: 'organizer_verification',
  );

  static const String organizerVerificationRenewalId = String.fromEnvironment(
    'GPB_ORGANIZER_VERIFICATION_RENEWAL_ID',
    defaultValue: 'organizer_verification_renewal',
  );

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
      'organizer_verification_renewal': organizerVerificationRenewalId,
    };
  }
}
