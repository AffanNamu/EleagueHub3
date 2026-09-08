// lib/core/services/country/country_analytics_service.dart
//
// Country detection FOR ANALYTICS ONLY — deliberately separate from
// CountryResolverService, which exists to pick a currency (NGN vs USD)
// and therefore ends its fallback chain in a hardcoded "NG" whenever
// detection fails. That's the right behavior for checkout; it's the
// wrong behavior for "where are our users actually located", since it
// silently inflates Nigeria's count with every failed resolution.
//
// This service reuses the SAME platform resolver (locale / IP lookup)
// but returns an EMPTY string on failure instead of guessing "NG".
// An empty result means "genuinely unknown" and should be treated that
// way everywhere it's read — including in the admin dashboard, which
// should show it as "Unknown" rather than omitting it silently.

import 'dart:ui';

import '../country/country_resolver_factory.dart';

class CountryAnalyticsService {
  CountryAnalyticsService._();
  static final CountryAnalyticsService instance = CountryAnalyticsService._();

  final CountryResolverPlatform _impl = createCountryResolverPlatform();

  bool _looksLikeCountryCode(String cc) => cc.trim().length == 2;

  /// Returns a two-letter ISO-3166-1 country code, or '' if it genuinely
  /// could not be determined. NEVER falls back to a guessed default —
  /// that's the entire point of this service existing separately from
  /// CountryResolverService.
  Future<String> resolveCountryCodeForAnalytics({Locale? locale}) async {
    try {
      final cc = (await _impl.resolveCountryCode(locale: locale)).trim().toUpperCase();
      return _looksLikeCountryCode(cc) ? cc : '';
    } catch (_) {
      return '';
    }
  }
}
