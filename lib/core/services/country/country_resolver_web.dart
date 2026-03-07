import 'dart:ui';

import 'country_resolver_platform.dart';

class WebCountryResolverPlatform implements CountryResolverPlatform {
  @override
  Future<String> resolveCountryCode({Locale? locale}) async {
    // Web: locale only (avoid CORS surprises).
    return (locale?.countryCode ?? '').trim().toUpperCase();
  }
}
