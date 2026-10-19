// lib/features/leagues/logic/region_locale_detector.dart
//
// Zero-permission "is this device likely in Europe" signal, used to
// surface Europe-relevant leagues first in the discovery list and to
// default a newly-created league's region. Deliberately NEVER touches
// any location/geolocation permission -- it only reads the device's
// already-configured locale (Locale.countryCode), the same
// `Localizations.maybeLocaleOf(context) ?? platformDispatcher.locale`
// signal already used elsewhere in this app (see
// master_league_payment_service.dart's _effectiveLocale) for country-
// dependent behavior. A locale is always available with no prompt; a
// missing/unknown country code is treated as "not Europe" (never
// assumed Europe by default), and nothing about this ever hides a
// league -- it only reorders them.

import 'dart:ui' show Locale;

import '../models/league.dart';

class RegionLocaleDetector {
  const RegionLocaleDetector._();

  /// Human-readable region value stored on a league created by an
  /// organizer whose device locale resolves to Europe. Leagues created
  /// before this feature (or by a non-European organizer) keep the
  /// pre-existing 'Global' default.
  static const String europeRegion = 'Europe';

  /// ISO 3166-1 alpha-2 codes for Europe (UN M49 "Europe" region,
  /// including the UK/EEA/EFTA states and Russia/Turkey's European
  /// reach, since this is a soft discovery signal, not a legal
  /// boundary).
  static const Set<String> _europeanCountryCodes = {
    'AD', 'AL', 'AT', 'AX', 'BA', 'BE', 'BG', 'BY', 'CH', 'CY', 'CZ', 'DE',
    'DK', 'EE', 'ES', 'FI', 'FO', 'FR', 'GB', 'GG', 'GI', 'GR', 'HR', 'HU',
    'IE', 'IM', 'IS', 'IT', 'JE', 'LI', 'LT', 'LU', 'LV', 'MC', 'MD', 'ME',
    'MK', 'MT', 'NL', 'NO', 'PL', 'PT', 'RO', 'RS', 'RU', 'SE', 'SI', 'SJ',
    'SK', 'SM', 'TR', 'UA', 'VA', 'XK',
  };

  /// Whether [locale]'s country code maps to a European country. Null or
  /// unrecognized codes return false -- a missing signal never defaults
  /// to "assume Europe".
  static bool isEuropeanLocale(Locale locale) {
    final code = locale.countryCode?.trim().toUpperCase();
    if (code == null || code.isEmpty) return false;
    return _europeanCountryCodes.contains(code);
  }

  /// Default `League.region` value for a league being created right now
  /// by someone whose device locale is [locale]. Preserves the
  /// pre-existing 'Global' default for everyone else.
  static String defaultRegionFor(Locale locale) =>
      isEuropeanLocale(locale) ? europeRegion : 'Global';

  /// Stable-sorts [leagues] so that, when [viewerLocale] is European,
  /// leagues whose region is [europeRegion] are moved ahead of every
  /// other league -- relative order is otherwise preserved exactly (a
  /// pure reorder, never a filter: every league the caller passed in is
  /// still present in the result). When [viewerLocale] is not European,
  /// returns [leagues] completely unchanged -- this is a per-viewer
  /// bias, not a global ranking change.
  static List<League> sortForViewer({
    required List<League> leagues,
    required Locale viewerLocale,
  }) {
    if (!isEuropeanLocale(viewerLocale)) return leagues;

    final european = <League>[];
    final rest = <League>[];
    for (final l in leagues) {
      if (l.region == europeRegion) {
        european.add(l);
      } else {
        rest.add(l);
      }
    }
    return [...european, ...rest];
  }
}
