import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'country_resolver_platform.dart';

class IoCountryResolverPlatform implements CountryResolverPlatform {
  static const Duration _timeout = Duration(seconds: 4);

  bool _looksLikeCountryCode(String cc) => cc.trim().length == 2;

  Future<String> _ipCountryCode() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('https://ipapi.co/country/')).timeout(_timeout);
      req.headers.set(HttpHeaders.acceptHeader, 'text/plain');
      final res = await req.close().timeout(_timeout);
      final body = await utf8.decodeStream(res).timeout(_timeout);
      final cc = body.trim().toUpperCase();
      if (_looksLikeCountryCode(cc)) return cc;
      return '';
    } catch (_) {
      return '';
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<String> resolveCountryCode({Locale? locale}) async {
    final localeCc = (locale?.countryCode ?? '').trim().toUpperCase();

    // If locale says NG, trust it immediately.
    if (localeCc == 'NG') return 'NG';

    // If locale is set to some other country (often US/GB), prefer IP lookup
    // so Nigerians with en_US still see NGN.
    final ipCc = await _ipCountryCode();
    if (_looksLikeCountryCode(ipCc)) return ipCc;

    // If IP lookup fails, fall back to locale country (if any).
    if (_looksLikeCountryCode(localeCc)) return localeCc;

    return '';
  }
}
