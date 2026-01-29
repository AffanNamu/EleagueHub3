import 'dart:ui';

class FlutterwavePricing {
  final String currency;

  /// String number format Flutterwave accepts (e.g. "4000" or "5").
  final String createLeagueAmount;

  /// String number format Flutterwave accepts (e.g. "1300" or "2").
  final String viewLeagueAmount;

  const FlutterwavePricing({
    required this.currency,
    required this.createLeagueAmount,
    required this.viewLeagueAmount,
  });
}

class FlutterwaveConfig {
  /// Never commit secret keys in the mobile app.
  /// We only use the public key on-device.
  ///
  /// You can override these using --dart-define if you want.
  static const String publicKey = String.fromEnvironment(
    'FLW_PUBLIC_KEY',
    defaultValue: 'FLWPUBK-04018360c1fb4ebed56dd005bb7fb381-X',
  );

  /// Must match the redirect url configured in Flutterwave settings.
  static const String redirectUrl = String.fromEnvironment(
    'FLW_REDIRECT_URL',
    defaultValue: 'https://esportlyic.workers.dev/flutterwave/webhook',
  );

  /// Flutterwave supported currency codes.
  static const String ngnCurrency = String.fromEnvironment('FLW_NGN_CURRENCY', defaultValue: 'NGN');
  static const String usdCurrency = String.fromEnvironment('FLW_USD_CURRENCY', defaultValue: 'USD');

  /// Defaults per your business rule:
  /// - Nigeria: NGN 4000 to create, NGN 1300 to view
  /// - Outside Nigeria: USD 5 to create, USD 2 to view
  static const String ngnCreateLeagueAmount =
      String.fromEnvironment('FLW_NGN_CREATE_LEAGUE_AMOUNT', defaultValue: '4000');
  static const String ngnViewLeagueAmount =
      String.fromEnvironment('FLW_NGN_VIEW_LEAGUE_AMOUNT', defaultValue: '1300');

  static const String usdCreateLeagueAmount =
      String.fromEnvironment('FLW_USD_CREATE_LEAGUE_AMOUNT', defaultValue: '5');
  static const String usdViewLeagueAmount =
      String.fromEnvironment('FLW_USD_VIEW_LEAGUE_AMOUNT', defaultValue: '2');

  static const bool isTestMode = bool.fromEnvironment('FLW_TEST_MODE', defaultValue: false);

  static bool isNigeriaCountryCode(String? countryCode) {
    final c = (countryCode ?? '').trim().toUpperCase();
    return c == 'NG';
  }

  static FlutterwavePricing pricingForLocale(Locale? locale) {
    final isNg = isNigeriaCountryCode(locale?.countryCode);
    if (isNg) {
      return const FlutterwavePricing(
        currency: ngnCurrency,
        createLeagueAmount: ngnCreateLeagueAmount,
        viewLeagueAmount: ngnViewLeagueAmount,
      );
    }
    return const FlutterwavePricing(
      currency: usdCurrency,
      createLeagueAmount: usdCreateLeagueAmount,
      viewLeagueAmount: usdViewLeagueAmount,
    );
  }

  static void assertConfigured() {
    if (publicKey.trim().isEmpty) {
      throw StateError('Flutterwave is not configured: FLW_PUBLIC_KEY is missing.');
    }
    if (redirectUrl.trim().isEmpty) {
      throw StateError('Flutterwave is not configured: FLW_REDIRECT_URL is missing.');
    }
  }

  static void assertValidPricing(FlutterwavePricing pricing) {
    if (pricing.currency.trim().isEmpty) {
      throw StateError('Flutterwave pricing invalid: currency is empty.');
    }
    final create = double.tryParse(pricing.createLeagueAmount.trim()) ?? 0;
    if (create <= 0) {
      throw StateError('Flutterwave pricing invalid: createLeagueAmount must be > 0.');
    }
    final view = double.tryParse(pricing.viewLeagueAmount.trim()) ?? 0;
    if (view <= 0) {
      throw StateError('Flutterwave pricing invalid: viewLeagueAmount must be > 0.');
    }
  }
}
