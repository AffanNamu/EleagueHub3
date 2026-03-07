import 'dart:ui';

import '../../config/flutterwave_config.dart';
import 'country_resolver_factory.dart';

/// Resolves user country code (ISO-3166-1 alpha-2) for currency selection:
///   NG -> NGN
///   other -> USD
///
/// Resolution order:
/// 1) FlutterwaveConfig.forcedCountryCode (testing override)
/// 2) locale.countryCode (if present)
/// 3) (IO only) IP lookup via ipapi.co/country
class CountryResolverService {
  CountryResolverService._();
  static final CountryResolverService instance = CountryResolverService._();

  final CountryResolverPlatform _impl = createCountryResolverPlatform();

  String _cached = '';
  DateTime? _cachedAt;

  bool get _cacheFresh {
    final at = _cachedAt;
    if (at == null) return false;
    return DateTime.now().difference(at).inHours < 6;
  }

  Future<String> resolveCountryCode({Locale? locale}) async {
    final forced = FlutterwaveConfig.forcedCountryCode.trim().toUpperCase();
    if (forced.isNotEmpty) return forced;

    if (_cacheFresh && _cached.isNotEmpty) return _cached;

    final cc = (await _impl.resolveCountryCode(locale: locale)).trim().toUpperCase();
    _cached = cc;
    _cachedAt = DateTime.now();
    return cc;
  }

  Future<bool> isNigeria({Locale? locale}) async {
    final cc = await resolveCountryCode(locale: locale);
    return cc == 'NG';
  }
}
