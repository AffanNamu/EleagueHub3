import '../../../features/master_leagues/domain/master_league_plan.dart';
import '../../config/payment_platform_config.dart';
import 'google_play_billing_catalog.dart';

class GooglePlayBillingService {
  const GooglePlayBillingService._();

  static const GooglePlayBillingService instance =
      GooglePlayBillingService._();

  bool get enabledForAndroid =>
      PaymentPlatformConfig.routeAndroidPaymentsToGooglePlayBilling;

  String _pendingMessage({
    required String flowLabel,
    required String productId,
    String extra = '',
  }) {
    final suffix = extra.trim().isEmpty ? '' : ' $extra';
    return 'Google Play Billing is enabled for Android for $flowLabel, '
        'but the Android billing client is not implemented yet. '
        'Planned product id: "$productId".$suffix '
        'Keep USE_GOOGLE_PLAY_BILLING_ANDROID=false to continue using '
        'Flutterwave on Android until the Play Billing integration is ready.';
  }

  String pendingPlanSubscriptionMessage({
    required MasterLeaguePlan plan,
    required PlanDuration duration,
  }) {
    final productId = GooglePlayBillingCatalog.subscriptionIdForPlan(
      plan: plan,
      duration: duration,
    );

    return _pendingMessage(
      flowLabel: '${plan.displayName} ${duration.displayName} subscription',
      productId: productId,
    );
  }

  String pendingOrganizerVerificationMessage() {
    return _pendingMessage(
      flowLabel: 'organizer verification payment',
      productId: GooglePlayBillingCatalog.organizerVerificationId,
    );
  }

  String pendingOrganizerVerificationRenewalMessage() {
    return _pendingMessage(
      flowLabel: 'organizer verification renewal payment',
      productId: GooglePlayBillingCatalog.organizerVerificationRenewalId,
    );
  }

  String pendingLeagueCreationMessage({
    required bool addonsOnly,
    required bool premiumUpgrade,
    required MasterLeaguePlan selectedPlan,
  }) {
    if (premiumUpgrade) {
      final productId = GooglePlayBillingCatalog.subscriptionIdForPlan(
        plan: selectedPlan,
        duration: PlanDuration.threeMonths,
      );
      return _pendingMessage(
        flowLabel: 'organizer plan upgrade from league creation flow',
        productId: productId,
        extra:
            'The current mobile upgrade mapping is scaffolded to the 3-month subscription SKU.',
      );
    }

    if (addonsOnly) {
      return _pendingMessage(
        flowLabel: 'league addons purchase',
        productId: GooglePlayBillingCatalog.leagueAddonsPackId,
        extra:
            'Dynamic coupon/add-on pricing still needs final Android product catalog design.',
      );
    }

    return _pendingMessage(
      flowLabel: 'league creation payment',
      productId: GooglePlayBillingCatalog.leagueCreationUnlockId,
    );
  }

  String pendingLeagueAccessUnlockMessage() {
    return _pendingMessage(
      flowLabel: 'league access unlock payment',
      productId: GooglePlayBillingCatalog.leagueAccessUnlockId,
    );
  }
}
