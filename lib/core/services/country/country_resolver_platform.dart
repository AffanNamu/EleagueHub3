import 'dart:ui';

/// Platform resolver contract.
/// Implementations must return an ISO-3166 country code (e.g., "NG", "US") or "".
abstract class CountryResolverPlatform {
  Future<String> resolveCountryCode({Locale? locale});
}
