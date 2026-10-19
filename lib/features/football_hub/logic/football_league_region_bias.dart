// lib/features/football_hub/logic/football_league_region_bias.dart
//
// Zero-permission "surface European competitions first" bias for the
// Football Hub's Matches tab. API-Football's /fixtures?date= endpoint
// returns every fixture happening worldwide on a given day with no
// regional ordering at all -- grouping by league (as the Matches tab
// already does) can put an obscure competition from anywhere in the
// world ahead of the Premier League or Bundesliga purely by API response
// order. This reorders those league groups -- it never drops one.
//
// Uses the SAME viewer-locale signal as
// lib/features/leagues/logic/region_locale_detector.dart (device
// Locale.countryCode, never the Geolocation API, never a permission
// prompt) to decide whether to apply the bias at all; the bias itself
// classifies each FIXTURE's league by its API-Football `country` name
// (e.g. "England", "Spain", "World" for UEFA club competitions), a
// completely different signal from the viewer's own locale.

import 'dart:ui' show Locale;

import '../../leagues/logic/region_locale_detector.dart';
import '../models/football_fixture.dart';

class FootballLeagueRegionBias {
  const FootballLeagueRegionBias._();

  /// Country names as API-Football represents them for UEFA's 55 member
  /// associations (the governing body for Europe's national leagues) --
  /// a soft relevance list, not a strict geography one, which is why a
  /// few transcontinental UEFA members (Russia, Turkey, Kazakhstan,
  /// Armenia, Azerbaijan, Georgia, Israel) are included alongside the
  /// mainland European countries. Spelling/hyphenation matches the
  /// domestic home-nations split API-Football itself uses for the UK.
  static const Set<String> _europeanCountryNames = {
    'England', 'Scotland', 'Wales', 'Northern Ireland', 'Northern-Ireland',
    'Ireland', 'Republic of Ireland', 'Spain', 'Italy', 'Germany', 'France',
    'Portugal', 'Netherlands', 'Belgium', 'Switzerland', 'Austria', 'Poland',
    'Turkey', 'Russia', 'Ukraine', 'Greece', 'Sweden', 'Norway', 'Denmark',
    'Finland', 'Iceland', 'Croatia', 'Serbia', 'Bosnia', 'Bosnia and Herzegovina',
    'Slovenia', 'Slovakia', 'Czech Republic', 'Czechia', 'Hungary', 'Romania',
    'Bulgaria', 'Albania', 'North Macedonia', 'Macedonia', 'Montenegro',
    'Kosovo', 'Moldova', 'Belarus', 'Lithuania', 'Latvia', 'Estonia',
    'Cyprus', 'Malta', 'Luxembourg', 'Andorra', 'Monaco', 'San Marino',
    'Liechtenstein', 'Vatican', 'Georgia', 'Armenia', 'Azerbaijan',
    'Kazakhstan', 'Israel',
  };

  /// UEFA club competitions API-Football files under country "World"
  /// rather than any single nation -- these are the well-known,
  /// stable API-Football league ids for them, already partly reflected
  /// in this screen's own `_popularLeagues` list (id 2).
  static const Set<int> _uefaInternationalLeagueIds = {
    2, // UEFA Champions League
    3, // UEFA Europa League
    848, // UEFA Europa Conference League
  };

  /// Whether a fixture's league should be treated as European for
  /// sorting purposes, by its country name or (for UEFA club
  /// competitions filed under "World") its league id.
  static bool isEuropeanLeague({required String country, required int leagueId}) {
    if (_uefaInternationalLeagueIds.contains(leagueId)) return true;
    return _europeanCountryNames.contains(country.trim());
  }

  /// Stable-sorts `leagueOrder` (a list of distinct league ids in
  /// first-seen order, as the Matches tab already builds it) so that,
  /// when `viewerLocale` is European, leagues classified as European by
  /// [isEuropeanLeague] move ahead of every other league -- relative
  /// order is otherwise preserved exactly (a pure reorder, never a
  /// filter: every league id passed in is still present in the result).
  /// When `viewerLocale` is not European, returns `leagueOrder`
  /// completely unchanged.
  static List<int> sortLeagueOrderForViewer({
    required List<int> leagueOrder,
    required Map<int, List<FootballFixture>> fixturesByLeague,
    required Locale viewerLocale,
  }) {
    if (!RegionLocaleDetector.isEuropeanLocale(viewerLocale)) return leagueOrder;

    final european = <int>[];
    final rest = <int>[];
    for (final leagueId in leagueOrder) {
      final group = fixturesByLeague[leagueId];
      final country = (group != null && group.isNotEmpty) ? group.first.leagueCountry : '';
      if (isEuropeanLeague(country: country, leagueId: leagueId)) {
        european.add(leagueId);
      } else {
        rest.add(leagueId);
      }
    }
    return [...european, ...rest];
  }
}
