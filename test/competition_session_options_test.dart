// test/competition_session_options_test.dart
//
// Covers the Dynamic Competition Session system's pure logic:
// CompetitionSessionOptions (generation/default/validation) and the
// League model's season field (round-trip + legacy-missing fallback).

import 'package:eleaguehub3/features/leagues/logic/competition_session_options.dart';
import 'package:eleaguehub3/features/leagues/models/league.dart';
import 'package:eleaguehub3/features/leagues/models/league_format.dart';
import 'package:eleaguehub3/features/leagues/models/league_settings.dart';
import 'package:eleaguehub3/features/leagues/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CompetitionSessionOptions.generate', () {
    test('produces 3 single years + 3 year ranges anchored to now', () {
      final options = CompetitionSessionOptions.generate(now: DateTime(2026, 6, 1));
      expect(options, [
        '2026',
        '2027',
        '2028',
        '2026/2027',
        '2027/2028',
        '2028/2029',
      ]);
    });

    test('is never anchored to a fixed year -- advances with the clock', () {
      final options2027 = CompetitionSessionOptions.generate(now: DateTime(2027, 1, 1));
      expect(options2027, [
        '2027',
        '2028',
        '2029',
        '2027/2028',
        '2028/2029',
        '2029/2030',
      ]);

      final options2030 = CompetitionSessionOptions.generate(now: DateTime(2030, 12, 31));
      expect(options2030.first, '2030');
    });
  });

  group('CompetitionSessionOptions.suggestedDefault', () {
    test('is the current/next year range, never forced', () {
      expect(
        CompetitionSessionOptions.suggestedDefault(now: DateTime(2026, 3, 1)),
        '2026/2027',
      );
      expect(
        CompetitionSessionOptions.suggestedDefault(now: DateTime(2030, 3, 1)),
        '2030/2031',
      );
    });
  });

  group('CompetitionSessionOptions.normalizeCustom', () {
    test('accepts a single year', () {
      expect(CompetitionSessionOptions.normalizeCustom('2026'), '2026');
    });

    test('accepts a year range', () {
      expect(CompetitionSessionOptions.normalizeCustom('2027/2028'), '2027/2028');
    });

    test('accepts an arbitrary custom label and trims whitespace', () {
      expect(
        CompetitionSessionOptions.normalizeCustom('  Summer Cup 2027  '),
        'Summer Cup 2027',
      );
    });

    test('rejects empty or whitespace-only input -- never silently falls back', () {
      expect(CompetitionSessionOptions.normalizeCustom(''), isNull);
      expect(CompetitionSessionOptions.normalizeCustom('   '), isNull);
    });

    test('rejects input beyond the max length', () {
      final tooLong = 'A' * (CompetitionSessionOptions.maxLength + 1);
      expect(CompetitionSessionOptions.normalizeCustom(tooLong), isNull);
    });

    test('accepts input right at the max length', () {
      final exact = 'A' * CompetitionSessionOptions.maxLength;
      expect(CompetitionSessionOptions.normalizeCustom(exact), exact);
    });
  });

  group('League.season round-trip', () {
    League baseLeague({String? season}) {
      return League(
        id: 'league-1',
        name: 'Gombi Championship',
        masterLeagueId: '',
        description: '',
        leagueImageUrl: '',
        sponsorImageUrl: '',
        viewerCapacity: 0,
        couponsEnabled: false,
        couponDiscountPercent: 0,
        couponCount: 0,
        homeAwayEnabled: false,
        format: LeagueFormat.classic,
        privacy: LeaguePrivacy.public,
        region: 'Global',
        maxTeams: 20,
        season: season ?? '2027/2028',
        organizerUid: 'organizer-uid',
        organizerUserId: 'organizer-uid',
        code: 'ABC123',
        qrPayloadOverride: '',
        settings: LeagueSettings.defaultsFor(LeagueFormat.classic),
        updatedAtMs: 0,
        version: 1,
      );
    }

    test('a single-year session round-trips through toJson/fromRemoteMap', () {
      final league = baseLeague(season: '2026');
      final roundTripped = League.fromRemoteMap(league.toJson());
      expect(roundTripped.season, '2026');
    });

    test('a year-range session round-trips unchanged', () {
      final league = baseLeague(season: '2027/2028');
      final roundTripped = League.fromRemoteMap(league.toJson());
      expect(roundTripped.season, '2027/2028');
    });

    test('a fully custom session label round-trips unchanged', () {
      final league = baseLeague(season: 'Summer Cup 2027');
      final roundTripped = League.fromRemoteMap(league.toJson());
      expect(roundTripped.season, 'Summer Cup 2027');
    });

    test(
      'an existing production doc with session already set to "2026" is preserved exactly -- '
      'never silently rewritten to a year range',
      () {
        final map = baseLeague(season: '2026').toJson();
        expect(League.fromRemoteMap(map).season, '2026');
      },
    );

    test(
      'a legacy doc genuinely missing the season field falls back to the frozen '
      'legacy default, not the current year',
      () {
        final map = baseLeague().toJson();
        map.remove('season');
        expect(League.fromRemoteMap(map).season, '2026');
      },
    );

    test('copyWith can change only the season, leaving every other field untouched', () {
      final league = baseLeague(season: '2026');
      final edited = league.copyWith(season: '2026/2027');

      expect(edited.season, '2026/2027');
      expect(edited.id, league.id);
      expect(edited.name, league.name);
      expect(edited.format, league.format);
      expect(edited.code, league.code);
    });
  });
}
