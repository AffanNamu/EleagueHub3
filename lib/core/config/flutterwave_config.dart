import 'dart:ui';

class FlutterwavePricing {
  final String currency;
  final String createLeagueAmount;
  final String viewLeagueAmount;

  const FlutterwavePricing({
    required this.currency,
    required this.createLeagueAmount,
    required this.viewLeagueAmount,
  });
}

class FlutterwaveConfig {
  static const bool isTestMode =
      bool.fromEnvironment('FLW_TEST_MODE', defaultValue: true);

  static const String publicKeyTest = String.fromEnvironment(
    'FLW_PUBLIC_KEY_TEST',
    defaultValue: 'FLWPUBK_TEST-65c33e45be4d1cfe5d417b10dfe692f0-X',
  );

  static const String publicKeyLive = String.fromEnvironment(
    'FLW_PUBLIC_KEY_LIVE',
    defaultValue: '',
  );

  static const String publicKeyFallback =
      String.fromEnvironment('FLW_PUBLIC_KEY', defaultValue: '');

  static const String redirectUrl = String.fromEnvironment(
    'FLW_REDIRECT_URL',
    defaultValue: 'https://esportlyic.workers.dev/flutterwave/webhook',
  );

  static const String forcedCountryCode =
      String.fromEnvironment('FLW_FORCE_COUNTRY', defaultValue: '');

  static const String ngnCurrency =
      String.fromEnvironment('FLW_NGN_CURRENCY', defaultValue: 'NGN');
  static const String usdCurrency =
      String.fromEnvironment('FLW_USD_CURRENCY', defaultValue: 'USD');

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

  static FlutterwavePricing pricingForLocale(Locale? locale) {
    final cc = (locale?.countryCode ?? '').trim().toUpperCase();
    if (isNigeriaCountryCode(cc)) {
      return const FlutterwavePricing(
        currency: ngnCurrency,
        createLeagueAmount: '0',
        viewLeagueAmount: '0',
      );
    }
    return const FlutterwavePricing(
      currency: usdCurrency,
      createLeagueAmount: '0',
      viewLeagueAmount: '0',
    );
  }

  static void assertConfigured() {
    final key = publicKey.trim();
    if (key.isEmpty) {
      if (isTestMode) {
        throw StateError(
          'Flutterwave TEST key missing: set FLW_PUBLIC_KEY_TEST via --dart-define.',
        );
      }
      throw StateError(
        'Flutterwave LIVE key missing: set FLW_PUBLIC_KEY_LIVE via --dart-define.',
      );
    }
    if (redirectUrl.trim().isEmpty) {
      throw StateError(
        'Flutterwave is not configured: FLW_REDIRECT_URL is missing.',
      );
    }
  }
}
