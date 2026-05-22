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

  static bool get isAndroidRuntime =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// True when we are running on Android AND the flag is enabled.
  /// This is the single gate used throughout the codebase.
  static bool get routeAndroidPaymentsToGooglePlayBilling =>
      isAndroidRuntime && useGooglePlayBillingOnAndroid;

  /// Web always uses Flutterwave.
  static bool get useFlutterwave =>
      kIsWeb || !routeAndroidPaymentsToGooglePlayBilling;

  static String pendingGooglePlayBillingMessage(String flowLabel) {
    return '$flowLabel is configured to use Google Play Billing on Android. '
        'Web continues to use Flutterwave.';
  }
}
