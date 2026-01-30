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
  /// TEST by default (as you requested).
  static const bool isTestMode = bool.fromEnvironment('FLW_TEST_MODE', defaultValue: true);

  /// Provide keys via --dart-define.
  ///
  /// TEST public key usually starts with: FLWPUBK_TEST-...
  static const String publicKeyTest = String.fromEnvironment('FLW_PUBLIC_KEY_TEST', defaultValue: '');

  /// LIVE public key usually starts with: FLWPUBK-...
  static const String publicKeyLive = String.fromEnvironment('FLW_PUBLIC_KEY_LIVE', defaultValue: '');

  /// Fallback key (optional): if you set only FLW_PUBLIC_KEY_TEST, you can also set FLW_PUBLIC_KEY.
  static const String publicKeyFallback = String.fromEnvironment('FLW_PUBLIC_KEY', defaultValue: '');

  /// Redirect URL used by the Flutterwave checkout flow.
  static const String redirectUrl = String.fromEnvironment(
    'FLW_REDIRECT_URL',
    defaultValue: 'https://esportlyic.workers.dev/flutterwave/webhook',
  );

  /// If we can't find any country code on device locales, we fall back to NG.
  static const String defaultCountryCode = String.fromEnvironment('FLW_DEFAULT_COUNTRY', defaultValue: 'NG');

  /// Optional hard override for testing:
  /// --dart-define=FLW_FORCE_COUNTRY=NG  OR  --dart-define=FLW_FORCE_COUNTRY=US
  static const String forcedCountryCode = String.fromEnvironment('FLW_FORCE_COUNTRY', defaultValue: '');

  static const String ngnCurrency = String.fromEnvironment('FLW_NGN_CURRENCY', defaultValue: 'NGN');
  static const String usdCurrency = String.fromEnvironment('FLW_USD_CURRENCY', defaultValue: 'USD');

  /// Your business pricing defaults:
  /// - Nigeria: NGN 4000 create, NGN 1300 view
  /// - Outside Nigeria: USD 5 create, USD 2 view
  static const String ngnCreateLeagueAmount =
      String.fromEnvironment('FLW_NGN_CREATE_LEAGUE_AMOUNT', defaultValue: '4000');
  static const String ngnViewLeagueAmount =
      String.fromEnvironment('FLW_NGN_VIEW_LEAGUE_AMOUNT', defaultValue: '1300');

  static const String usdCreateLeagueAmount =
      String.fromEnvironment('FLW_USD_CREATE_LEAGUE_AMOUNT', defaultValue: '5');
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

  static bool _anyDeviceLocaleIsNigeria() {
    try {
      final locales = PlatformDispatcher.instance.locales;
      for (final l in locales) {
        final cc = (l.countryCode ?? '').trim().toUpperCase();
        if (cc == 'NG') return true;
      }
    } catch (_) {}
    return false;
  }

  static FlutterwavePricing pricingForLocale(Locale? locale) {
    // Highest priority: forced override
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

    // Next: if any device locale includes NG, treat as Nigeria
    if (_anyDeviceLocaleIsNigeria()) {
      return const FlutterwavePricing(
        currency: ngnCurrency,
        createLeagueAmount: ngnCreateLeagueAmount,
        viewLeagueAmount: ngnViewLeagueAmount,
      );
    }

    // Next: use provided locale countryCode, else fallback to defaultCountryCode (NG)
    String country = (locale?.countryCode ?? '').trim().toUpperCase();
    if (country.isEmpty) {
      country = defaultCountryCode.trim().toUpperCase();
    }

    if (isNigeriaCountryCode(country)) {
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
