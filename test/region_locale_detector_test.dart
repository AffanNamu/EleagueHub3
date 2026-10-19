// test/region_locale_detector_test.dart
//
// Regression coverage for the zero-permission locale-based "show Europe
// first" sort bias: it must reorder leagues (never filter/hide any), do
// nothing at all for a non-European viewer, and never assume Europe when
// the locale's country code is missing or unrecognized.
// See lib/features/leagues/logic/region_locale_detector.dart.

import 'dart:ui';

import 'package:eleaguehub3/features/leagues/logic/region_locale_detector.dart';
import 'package:eleaguehub3/features/leagues/models/enums.dart';
import 'package:eleaguehub3/features/leagues/models/league.dart';
import 'package:eleaguehub3/features/leagues/models/league_format.dart';
import 'package:eleaguehub3/features/leagues/models/league_settings.dart';
import 'package:flutter_test/flutter_test.dart';

League _league({required String id, required String region}) {
  return League(
    id: id,
    name: id,
    format: LeagueFormat.classic,
    privacy: LeaguePrivacy.public,
    region: region,
    maxTeams: 20,
    season: '2026',
    organizerUid: 'org',
    organizerUserId: 'org',
    code: id,
    qrPayloadOverride: '',
    settings: LeagueSettings.defaultsFor(LeagueFormat.classic),
    updatedAtMs: 0,
    version: 1,
  );
}

void main() {
  group('RegionLocaleDetector.isEuropeanLocale', () {
    test('recognized European country codes return true', () {
      expect(RegionLocaleDetector.isEuropeanLocale(const Locale('en', 'GB')), isTrue);
      expect(RegionLocaleDetector.isEuropeanLocale(const Locale('de', 'DE')), isTrue);
      expect(RegionLocaleDetector.isEuropeanLocale(const Locale('fr', 'FR')), isTrue);
      expect(RegionLocaleDetector.isEuropeanLocale(const Locale('it', 'IT')), isTrue);
    });

    test('non-European country codes return false', () {
      expect(RegionLocaleDetector.isEuropeanLocale(const Locale('en', 'US')), isFalse);
      expect(RegionLocaleDetector.isEuropeanLocale(const Locale('en', 'NG')), isFalse);
      expect(RegionLocaleDetector.isEuropeanLocale(const Locale('pt', 'BR')), isFalse);
      expect(RegionLocaleDetector.isEuropeanLocale(const Locale('ja', 'JP')), isFalse);
    });

    test('a locale with no country code is never assumed to be Europe', () {
      expect(RegionLocaleDetector.isEuropeanLocale(const Locale('en')), isFalse);
      expect(RegionLocaleDetector.isEuropeanLocale(const Locale('fr')), isFalse);
    });

    test('language code alone never decides it -- only the country code matters', () {
      // 'en' is spoken in both GB (Europe) and US/NG (not) -- the
      // language must never be used as a region proxy by itself.
      expect(RegionLocaleDetector.isEuropeanLocale(const Locale('en', 'GB')), isTrue);
      expect(RegionLocaleDetector.isEuropeanLocale(const Locale('en', 'US')), isFalse);
    });
  });

  group('RegionLocaleDetector.defaultRegionFor', () {
    test('European locale defaults to Europe', () {
      expect(RegionLocaleDetector.defaultRegionFor(const Locale('de', 'DE')), 'Europe');
    });

    test('non-European locale keeps the pre-existing Global default', () {
      expect(RegionLocaleDetector.defaultRegionFor(const Locale('en', 'US')), 'Global');
    });
  });

  group('RegionLocaleDetector.sortForViewer', () {
    test('non-European viewer: list is returned completely unchanged', () {
      final leagues = [
        _league(id: 'a', region: 'Global'),
        _league(id: 'b', region: 'Europe'),
        _league(id: 'c', region: 'Global'),
      ];
      final sorted = RegionLocaleDetector.sortForViewer(
        leagues: leagues,
        viewerLocale: const Locale('en', 'US'),
      );
      expect(sorted.map((l) => l.id).toList(), ['a', 'b', 'c']);
    });

    test('European viewer: Europe-tagged leagues move to the front, relative order preserved within each group', () {
      final leagues = [
        _league(id: 'a', region: 'Global'),
        _league(id: 'b', region: 'Europe'),
        _league(id: 'c', region: 'Global'),
        _league(id: 'd', region: 'Europe'),
      ];
      final sorted = RegionLocaleDetector.sortForViewer(
        leagues: leagues,
        viewerLocale: const Locale('fr', 'FR'),
      );
      expect(sorted.map((l) => l.id).toList(), ['b', 'd', 'a', 'c']);
    });

    test('every league passed in is still present -- this is a reorder, never a filter', () {
      final leagues = [
        _league(id: 'a', region: 'Global'),
        _league(id: 'b', region: 'Europe'),
        _league(id: 'c', region: 'Asia'),
      ];
      final sorted = RegionLocaleDetector.sortForViewer(
        leagues: leagues,
        viewerLocale: const Locale('es', 'ES'),
      );
      expect(sorted.length, leagues.length);
      expect(sorted.map((l) => l.id).toSet(), leagues.map((l) => l.id).toSet());
    });

    test('no Europe-tagged leagues at all: European viewer still gets every league, unchanged order', () {
      final leagues = [
        _league(id: 'a', region: 'Global'),
        _league(id: 'b', region: 'Global'),
      ];
      final sorted = RegionLocaleDetector.sortForViewer(
        leagues: leagues,
        viewerLocale: const Locale('nl', 'NL'),
      );
      expect(sorted.map((l) => l.id).toList(), ['a', 'b']);
    });
  });
}
