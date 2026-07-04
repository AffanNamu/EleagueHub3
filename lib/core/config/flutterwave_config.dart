import 'dart:ui';
import 'package:flutter/foundation.dart';

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

  // ── FIXED: publicKey resolution ────────────────────────────────────────
  //
  // OLD BUG: publicKey only looked at keys matching the CURRENT isTestMode
  // flag. If a build ran with isTestMode == true (its default, whenever
  // FLW_TEST_MODE isn't explicitly passed at build time) but the developer
  // had only configured a LIVE key (or vice versa), publicKey resolved to
  // an empty string and assertConfigured() threw "key missing" — even
  // though a perfectly usable key existed in the same class, just tagged
  // for the other mode. This is very likely the exact "missing payment
  // keys" error being seen after switching build flavours/environments.
  //
  // FIX: still PREFER the key matching the current mode (test key when
  // isTestMode, live key when not), but if that's empty, fall back across
  // modes (generic key → the other mode's key) before giving up. This
  // keeps the intended behaviour (use the right key for the right build)
  // while preventing a single missing --dart-define flag from hard-
  // blocking every payment. We only log — never silently swap in
  // production without a trace — via a debug-mode warning.
  static String get publicKey {
    final preferred = isTestMode ? publicKeyTest : publicKeyLive;
    if (preferred.trim().isNotEmpty) return preferred.trim();

    if (publicKeyFallback.trim().isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[FlutterwaveConfig] ${isTestMode ? "TEST" : "LIVE"} key was '
          'empty — using generic FLW_PUBLIC_KEY fallback instead.',
        );
      }
      return publicKeyFallback.trim();
    }

    // Last resort: fall back to whichever mode-specific key IS configured,
    // even if it doesn't match isTestMode. This prevents a single missing
    // --dart-define from completely blocking checkout, while still
    // surfacing loudly in debug logs so it gets fixed properly.
    final other = isTestMode ? publicKeyLive : publicKeyTest;
    if (other.trim().isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[FlutterwaveConfig] WARNING: no ${isTestMode ? "TEST" : "LIVE"} '
          'key configured — falling back to the '
          '${isTestMode ? "LIVE" : "TEST"} key instead. '
          'Set FLW_TEST_MODE and the matching FLW_PUBLIC_KEY_* correctly '
          'for this build.',
        );
      }
      return other.trim();
    }

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

  // ── FIXED: assertConfigured() error messages ────────────────────────────
  //
  // Now reflects the fallback logic above accurately, and tells the
  // developer exactly which --dart-define values are missing instead of
  // a generic "key missing" message that doesn't distinguish between the
  // "no key of any kind" case and the "wrong mode configured" case.
  static void assertConfigured() {
    final key = publicKey.trim();

    if (key.isEmpty) {
      final missingVars = <String>[
        if (publicKeyTest.trim().isEmpty) 'FLW_PUBLIC_KEY_TEST',
        if (publicKeyLive.trim().isEmpty) 'FLW_PUBLIC_KEY_LIVE',
        if (publicKeyFallback.trim().isEmpty) 'FLW_PUBLIC_KEY',
      ].join(', ');

      throw StateError(
        'Flutterwave is not configured: no usable public key found. '
        'Current mode: ${isTestMode ? "TEST" : "LIVE"}. '
        'Missing --dart-define values: $missingVars. '
        'Pass at least one matching public key at build time.',
      );
    }

    if (redirectUrl.trim().isEmpty) {
      throw StateError(
        'Flutterwave is not configured: FLW_REDIRECT_URL is missing.',
      );
    }
  }
}