import 'package:flutter/foundation.dart';

class PaymentPlatformConfig {
  const PaymentPlatformConfig._();

  static const bool useGooglePlayBillingOnAndroid =
      bool.fromEnvironment(
        'USE_GOOGLE_PLAY_BILLING_ANDROID',
        defaultValue: false,
      );

  static bool get isAndroidRuntime =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get routeAndroidPaymentsToGooglePlayBilling =>
      isAndroidRuntime && useGooglePlayBillingOnAndroid;

  static String pendingGooglePlayBillingMessage(String flowLabel) {
    return '$flowLabel is configured to use Google Play Billing on Android, '
        'but that integration is not implemented yet. Web continues to use '
        'Flutterwave. For now, keep '
        'USE_GOOGLE_PLAY_BILLING_ANDROID=false to preserve the current '
        'Flutterwave payment flow.';
  }
}
