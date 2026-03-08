import 'dart:ui';

import '../../config/flutterwave_config.dart';
import 'country_resolver_factory.dart';

/// Resolves user country code (ISO-3166-1 alpha-2) for currency selection:
///   NG -> NGN
///   other -> USD
///
/// Resolution order:
/// 1) FlutterwaveConfig.forcedCountryCode (testing override)
/// 2) platform resolver (locale countryCode, with IO IP-lookup fallback)
/// 3) FINAL FALLBACK (Nigeria-first): "NG"
///
/// Why Nigeria-first fallback?
/// Some devices/builds return locale without a countryCode (e.g., "en").
/// In that scenario you prefer showing NGN rather than USD.
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

  bool _looksLikeCountryCode(String cc) => cc.trim().length == 2;

  Future<String> resolveCountryCode({Locale? locale}) async {
    // 1) Explicit override for testing
    final forced = FlutterwaveConfig.forcedCountryCode.trim().toUpperCase();
    if (_looksLikeCountryCode(forced)) return forced;

    // 2) Cached
    if (_cacheFresh && _looksLikeCountryCode(_cached)) return _cached;

    // 3) Platform resolver (locale / IP)
    String cc = '';
    try {
      cc = (await _impl.resolveCountryCode(locale: locale)).trim().toUpperCase();
    } catch (_) {
      cc = '';
    }

    // 4) Final fallback: Nigeria-first
    if (!_looksLikeCountryCode(cc)) {
      cc = 'NG';
    }

    _cached = cc;
    _cachedAt = DateTime.now();
    return cc;
  }

  Future<bool> isNigeria({Locale? locale}) async {
    final cc = await resolveCountryCode(locale: locale);
    return cc == 'NG';
  }
}
