// lib/core/config/payment_platform_config.dart
import 'package:flutter/foundation.dart';

class PaymentPlatformConfig {
  const PaymentPlatformConfig._();

  /// Set to true to route Android payments through Google Play Billing.
  /// On web we always use Flutterwave regardless of this flag.
  /// Defaults to TRUE so that Play Store submissions use the correct
  /// billing system and comply with Google Play policy.
  static const bool useGooglePlayBillingOnAndroid =
      bool.fromEnvironment(
        'USE_GOOGLE_PLAY_BILLING_ANDROID',
        defaultValue: true, // ← changed from false to true
      );

  // ── NEW: iOS routing ──────────────────────────────────────────────────
  //
  // Unlike Android, this is NOT behind a flag you can turn off. Apple's
  // App Store Review Guideline 3.1.1 requires In-App Purchase (StoreKit)
  // for any digital content/feature unlocked inside the app — which is
  // exactly what league creation, league viewing, plan subscriptions,
  // premium subscription, and organizer verification all are. Shipping
  // Flutterwave for these on iOS is a near-certain rejection, so this
  // has no env-var override the way the Android flag does.
  static bool get isIOSRuntime =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get routeIOSPaymentsToStoreKit => isIOSRuntime;

  static bool get isAndroidRuntime =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// True when we are running on Android AND the flag is enabled.
  /// This is the single gate used throughout the codebase.
  static bool get routeAndroidPaymentsToGooglePlayBilling =>
      isAndroidRuntime && useGooglePlayBillingOnAndroid;

  /// NEW: true when this platform should use a native store's IAP
  /// mechanism at all (Google Play Billing OR StoreKit), regardless of
  /// which one specifically. Prefer this over checking
  /// routeAndroidPaymentsToGooglePlayBilling alone in any NEW call site
  /// so it automatically covers iOS too. Existing call sites that check
  /// routeAndroidPaymentsToGooglePlayBilling directly still work exactly
  /// as before on Android — they just won't automatically get iOS
  /// coverage until they're updated to check this instead.
  static bool get useNativeInAppPurchase =>
      routeAndroidPaymentsToGooglePlayBilling || routeIOSPaymentsToStoreKit;

  /// Paid league access (the viewer/participant charge on Champions-League
  /// format leagues and on full classic leagues) is not sold in the
  /// store-distributed apps: there is no App Store or Google Play product
  /// for it, and organizers are covered by the Pro/Elite plans. On those
  /// builds such leagues open without a charge and no unlock/pay sheet is
  /// shown. Web (Flutterwave) keeps its existing behaviour.
  static bool get offerPaidLeagueAccess => !useNativeInAppPurchase;

  /// Web always uses Flutterwave. Android/iOS use Flutterwave only when
  /// their respective native-IAP gate above is off.
  static bool get useFlutterwave => kIsWeb || !useNativeInAppPurchase;
}
