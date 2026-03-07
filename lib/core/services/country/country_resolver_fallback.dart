import 'dart:ui';

import 'country_resolver_platform.dart';

/// Default/fallback implementation (works everywhere).
/// Uses only locale.countryCode (no network).
class FallbackCountryResolverPlatform implements CountryResolverPlatform {
  @override
  Future<String> resolveCountryCode({Locale? locale}) async {
    return (locale?.countryCode ?? '').trim().toUpperCase();
  }
}
