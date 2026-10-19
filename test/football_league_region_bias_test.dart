// test/football_league_region_bias_test.dart
//
// Regression coverage for the Football Hub Matches tab's zero-permission
// "show European competitions first" sort bias: it must reorder league
// groups (never drop one), recognize UEFA club competitions filed under
// country "World", and do nothing at all for a non-European viewer.
// See lib/features/football_hub/logic/football_league_region_bias.dart.

import 'dart:ui';

import 'package:eleaguehub3/features/football_hub/logic/football_league_region_bias.dart';
import 'package:eleaguehub3/features/football_hub/models/football_fixture.dart';
import 'package:flutter_test/flutter_test.dart';

FootballFixture _fixture({
  required int leagueId,
  required String country,
  int id = 1,
}) {
  return FootballFixture(
    id: id,
    kickoff: DateTime(2026, 1, 1),
    statusShort: 'NS',
    statusLong: 'Not Started',
    elapsedMinutes: null,
    leagueId: leagueId,
    leagueName: 'League $leagueId',
    leagueLogoUrl: '',
    leagueCountry: country,
    round: 'Regular Season - 1',
    season: 2026,
    homeTeamId: 1,
    homeTeamName: 'Home',
    homeTeamLogoUrl: '',
    awayTeamId: 2,
    awayTeamName: 'Away',
    awayTeamLogoUrl: '',
    homeGoals: null,
    awayGoals: null,
  );
}

void main() {
  group('FootballLeagueRegionBias.isEuropeanLeague', () {
    test('recognized European country names are European', () {
      expect(FootballLeagueRegionBias.isEuropeanLeague(country: 'England', leagueId: 39), isTrue);
      expect(FootballLeagueRegionBias.isEuropeanLeague(country: 'Spain', leagueId: 140), isTrue);
      expect(FootballLeagueRegionBias.isEuropeanLeague(country: 'Germany', leagueId: 78), isTrue);
    });

    test('non-European country names are not European', () {
      expect(FootballLeagueRegionBias.isEuropeanLeague(country: 'Brazil', leagueId: 71), isFalse);
      expect(FootballLeagueRegionBias.isEuropeanLeague(country: 'USA', leagueId: 253), isFalse);
      expect(FootballLeagueRegionBias.isEuropeanLeague(country: 'Japan', leagueId: 98), isFalse);
    });

    test('UEFA club competitions filed under country "World" are still European by league id', () {
      expect(FootballLeagueRegionBias.isEuropeanLeague(country: 'World', leagueId: 2), isTrue); // Champions League
      expect(FootballLeagueRegionBias.isEuropeanLeague(country: 'World', leagueId: 3), isTrue); // Europa League
      expect(FootballLeagueRegionBias.isEuropeanLeague(country: 'World', leagueId: 848), isTrue); // Conference League
    });

    test('an unrelated "World" competition (not a known UEFA id) is not assumed European', () {
      expect(FootballLeagueRegionBias.isEuropeanLeague(country: 'World', leagueId: 1), isFalse);
    });
  });

  group('FootballLeagueRegionBias.sortLeagueOrderForViewer', () {
    test('non-European viewer: league order is returned completely unchanged', () {
      final byLeague = {
        1: [_fixture(leagueId: 1, country: 'Brazil')],
        2: [_fixture(leagueId: 2, country: 'England')],
        3: [_fixture(leagueId: 3, country: 'Japan')],
      };
      final sorted = FootballLeagueRegionBias.sortLeagueOrderForViewer(
        leagueOrder: [1, 2, 3],
        fixturesByLeague: byLeague,
        viewerLocale: const Locale('pt', 'BR'),
      );
      expect(sorted, [1, 2, 3]);
    });

    test('European viewer: European leagues move to the front, relative order preserved within each group', () {
      final byLeague = {
        71: [_fixture(leagueId: 71, country: 'Brazil')],
        39: [_fixture(leagueId: 39, country: 'England')],
        98: [_fixture(leagueId: 98, country: 'Japan')],
        140: [_fixture(leagueId: 140, country: 'Spain')],
      };
      final sorted = FootballLeagueRegionBias.sortLeagueOrderForViewer(
        leagueOrder: [71, 39, 98, 140],
        fixturesByLeague: byLeague,
        viewerLocale: const Locale('fr', 'FR'),
      );
      expect(sorted, [39, 140, 71, 98]);
    });

    test('every league id passed in is still present -- this is a reorder, never a filter', () {
      final byLeague = {
        71: [_fixture(leagueId: 71, country: 'Brazil')],
        39: [_fixture(leagueId: 39, country: 'England')],
      };
      final sorted = FootballLeagueRegionBias.sortLeagueOrderForViewer(
        leagueOrder: [71, 39],
        fixturesByLeague: byLeague,
        viewerLocale: const Locale('de', 'DE'),
      );
      expect(sorted.toSet(), {71, 39});
      expect(sorted.length, 2);
    });

    test('European viewer: a UEFA club competition under "World" still floats to the top', () {
      final byLeague = {
        71: [_fixture(leagueId: 71, country: 'Brazil')],
        2: [_fixture(leagueId: 2, country: 'World')], // Champions League
      };
      final sorted = FootballLeagueRegionBias.sortLeagueOrderForViewer(
        leagueOrder: [71, 2],
        fixturesByLeague: byLeague,
        viewerLocale: const Locale('it', 'IT'),
      );
      expect(sorted, [2, 71]);
    });

    test('no European leagues at all: European viewer still gets every league, unchanged order', () {
      final byLeague = {
        71: [_fixture(leagueId: 71, country: 'Brazil')],
        98: [_fixture(leagueId: 98, country: 'Japan')],
      };
      final sorted = FootballLeagueRegionBias.sortLeagueOrderForViewer(
        leagueOrder: [71, 98],
        fixturesByLeague: byLeague,
        viewerLocale: const Locale('nl', 'NL'),
      );
      expect(sorted, [71, 98]);
    });
  });
}
