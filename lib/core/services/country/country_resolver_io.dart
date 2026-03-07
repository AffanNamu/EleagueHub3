import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'country_resolver_platform.dart';

class IoCountryResolverPlatform implements CountryResolverPlatform {
  static const Duration _timeout = Duration(seconds: 4);

  Future<String> _ipCountryCode() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('https://ipapi.co/country/')).timeout(_timeout);
      req.headers.set(HttpHeaders.acceptHeader, 'text/plain');
      final res = await req.close().timeout(_timeout);
      final body = await utf8.decodeStream(res).timeout(_timeout);
      final cc = body.trim().toUpperCase();
      if (cc.length == 2) return cc;
      return '';
    } catch (_) {
      return '';
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<String> resolveCountryCode({Locale? locale}) async {
    final cc = (locale?.countryCode ?? '').trim().toUpperCase();
    if (cc.length == 2) return cc;

    // Fallback: IP lookup (best-effort).
    return _ipCountryCode();
  }
}
