import 'dart:ui';

class FlutterwavePricing {
  final String currency;

  /// String number format Flutterwave accepts (e.g. "4000" or "5").
  final String createLeagueAmount;

  /// String number format Flutterwave accepts (e.g. "1500" or "2").
  ///
  /// NOTE:
  /// This amount is used in two places in the current app:
  /// 1) League access charges (LeagueAccessGuard)
  /// 2) Viewer capacity add-on unit price during league creation payment
  ///
  /// We also reuse it as the coupon unit fee during league creation payment
  /// (as requested: coupon fee == viewer fee).
  final String viewLeagueAmount;

  const FlutterwavePricing({
    required this.currency,
    required this.createLeagueAmount,
    required this.viewLeagueAmount,
  });
}

class FlutterwaveConfig {
  /// TEST mode by default (as requested).
  static const bool isTestMode = bool.fromEnvironment('FLW_TEST_MODE', defaultValue: true);

  /// IMPORTANT:
  /// - Keep SECRET keys out of the app.
  /// - We only use PUBLIC keys on-device.
  ///
  /// You can still override these via --dart-define in CI/CD.
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

  /// Nigeria-first pricing (fixes "shows $5 while I'm in Nigeria").
  ///
  /// This forces NG by default so your app shows NGN pricing on Nigerian devices even if
  /// the phone locale is set to US/UK.
  ///
  /// If you want to test International pricing on your own device:
  /// flutter run --dart-define=FLW_FORCE_COUNTRY=US
  static const String forcedCountryCode = String.fromEnvironment('FLW_FORCE_COUNTRY', defaultValue: 'NG');

  static const String ngnCurrency = String.fromEnvironment('FLW_NGN_CURRENCY', defaultValue: 'NGN');
  static const String usdCurrency = String.fromEnvironment('FLW_USD_CURRENCY', defaultValue: 'USD');

  /// Updated business pricing defaults (as requested):
  /// - Nigeria: NGN 1500 create, NGN 1500 view
  /// - Outside Nigeria: USD 2 create, USD 2 view
  ///
  /// You can still override via --dart-define.
  static const String ngnCreateLeagueAmount =
      String.fromEnvironment('FLW_NGN_CREATE_LEAGUE_AMOUNT', defaultValue: '1500');
  static const String ngnViewLeagueAmount =
      String.fromEnvironment('FLW_NGN_VIEW_LEAGUE_AMOUNT', defaultValue: '1500');

  static const String usdCreateLeagueAmount =
      String.fromEnvironment('FLW_USD_CREATE_LEAGUE_AMOUNT', defaultValue: '2');
  static const String usdViewLeagueAmount =
      String.fromEnvironment('FLW_USD_VIEW_LEAGUE_AMOUNT', defaultValue: '2');

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
    final forced = forcedCountryCode.trim().toUpperCase();
    if (forced.isNotEmpty) {
      if (isNigeriaCountryCode(forced)) {
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

    final cc = (locale?.countryCode ?? '').trim().toUpperCase();
    if (isNigeriaCountryCode(cc)) {
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
