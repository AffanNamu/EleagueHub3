import 'dart:ui';

/// NOTE:
/// Pricing is no longer sourced from this file.
/// All pricing must come from Firestore: app_config/pricing (with fallback to app/pricing).
///
/// This file now only contains Flutterwave runtime configuration (public keys, redirect URL)
/// and an OPTIONAL forced country override for testing.
class FlutterwavePricing {
  final String currency;

  /// String number format Flutterwave accepts (e.g. "4000" or "5").
  final String createLeagueAmount;

  /// String number format Flutterwave accepts (e.g. "1500" or "2").
  final String viewLeagueAmount;

  const FlutterwavePricing({
    required this.currency,
    required this.createLeagueAmount,
    required this.viewLeagueAmount,
  });
}

class FlutterwaveConfig {
  /// TEST mode by default.
  static const bool isTestMode = bool.fromEnvironment('FLW_TEST_MODE', defaultValue: true);

  /// IMPORTANT:
  /// - Keep SECRET keys out of the app.
  /// - Only PUBLIC keys are allowed on-device.
  static const String publicKeyTest = String.fromEnvironment(
    'FLW_PUBLIC_KEY_TEST',
    defaultValue: 'FLWPUBK_TEST-65c33e45be4d1cfe5d417b10dfe692f0-X',
  );

  static const String publicKeyLive = String.fromEnvironment(
    'FLW_PUBLIC_KEY_LIVE',
    defaultValue: '',
  );

  /// Optional fallback if you prefer a single key name:
  static const String publicKeyFallback = String.fromEnvironment('FLW_PUBLIC_KEY', defaultValue: '');

  /// Redirect URL used by the Flutterwave checkout flow.
  static const String redirectUrl = String.fromEnvironment(
    'FLW_REDIRECT_URL',
    defaultValue: 'https://esportlyic.workers.dev/flutterwave/webhook',
  );

  /// Optional country override for testing.
  ///
  /// Examples:
  ///   flutter run --dart-define=FLW_FORCE_COUNTRY=NG
  ///   flutter run --dart-define=FLW_FORCE_COUNTRY=US
  ///
  /// Default is empty so the app uses automatic detection.
  static const String forcedCountryCode = String.fromEnvironment('FLW_FORCE_COUNTRY', defaultValue: '');

  static const String ngnCurrency = String.fromEnvironment('FLW_NGN_CURRENCY', defaultValue: 'NGN');
  static const String usdCurrency = String.fromEnvironment('FLW_USD_CURRENCY', defaultValue: 'USD');

  static String get publicKey {
    if (isTestMode) {
      if (publicKeyTest.trim().isNotEmpty) return publicKeyTest.trim();
      if (publicKeyFallback.trim().isNotEmpty) return publicKeyFallback.trim();
      return '';
    }

    if (publicKeyLive.trim().isNotEmpty) return publicKeyLive.trim();
    if (publicKeyFallback.trim().isNotEmpty) return publicKeyFallback.trim();
    return '';
  }

  static bool isNigeriaCountryCode(String? countryCode) {
    final c = (countryCode ?? '').trim().toUpperCase();
    return c == 'NG';
  }

  /// Deprecated legacy helper (kept only to avoid breaking older UI code).
  /// Pricing must come from Firestore now.
  static FlutterwavePricing pricingForLocale(Locale? locale) {
    final cc = (locale?.countryCode ?? '').trim().toUpperCase();
    if (isNigeriaCountryCode(cc)) {
      return const FlutterwavePricing(currency: ngnCurrency, createLeagueAmount: '0', viewLeagueAmount: '0');
    }
    return const FlutterwavePricing(currency: usdCurrency, createLeagueAmount: '0', viewLeagueAmount: '0');
  }

  static void assertConfigured() {
    final key = publicKey.trim();
    if (key.isEmpty) {
      if (isTestMode) {
        throw StateError('Flutterwave TEST key missing: set FLW_PUBLIC_KEY_TEST via --dart-define.');
      }
      throw StateError('Flutterwave LIVE key missing: set FLW_PUBLIC_KEY_LIVE via --dart-define.');
    }
    if (redirectUrl.trim().isEmpty) {
      throw StateError('Flutterwave is not configured: FLW_REDIRECT_URL is missing.');
    }
  }
}
