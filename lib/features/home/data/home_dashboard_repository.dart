// lib/features/home/data/home_dashboard_repository.dart
//
// Aggregates real data the user already has across their own leagues
// (never invented/placeholder data) for the Home tab's quick-glance
// sections: featured standings, latest highlight, and upcoming fixtures.
// Deliberately Future-based (one-shot loads), matching how the rest of
// this screen already loads its own state (see _HomeBannerAdSlot).

import '../../highlights/data/highlights_feed_repository_firebase.dart';
import '../../highlights/domain/match_highlight.dart';
import '../../leagues/data/leagues_repository_local.dart';
import '../../leagues/domain/standings/standings_calculator.dart';
import '../../leagues/models/enums.dart';
import '../../leagues/models/fixture_match.dart';
import '../../leagues/models/league.dart';
import '../../leagues/models/team.dart';

class HomeStandingsSummary {
  const HomeStandingsSummary({
    required this.league,
    required this.position,
    required this.totalTeams,
    required this.played,
    required this.points,
  });

  final League league;
  final int position;
  final int totalTeams;
  final int played;
  final int points;
}

class HomeUpcomingFixture {
  const HomeUpcomingFixture({
    required this.league,
    required this.match,
    required this.homeTeam,
    required this.awayTeam,
  });

  final League league;
  final FixtureMatch match;
  final Team homeTeam;
  final Team awayTeam;
}

class HomeLatestHighlight {
  const HomeLatestHighlight({required this.league, required this.highlight});

  final League league;
  final MatchHighlight highlight;
}

class HomeDashboardRepository {
  HomeDashboardRepository({
    required LocalLeaguesRepository leaguesRepo,
    HighlightsFeedRepositoryFirebase? highlightsRepo,
  })  : _leaguesRepo = leaguesRepo,
        _highlightsRepo = highlightsRepo ?? HighlightsFeedRepositoryFirebase();

  final LocalLeaguesRepository _leaguesRepo;
  final HighlightsFeedRepositoryFirebase _highlightsRepo;

  // Bounds how many of the user's leagues we scan per section, so a user
  // in many leagues never triggers an unbounded fan-out of Firestore reads.
  static const int _maxLeaguesScanned = 6;

  Future<List<League>> _recentLeagues() async {
    final leagues = await _leaguesRepo.listLeagues();
    final sorted = [...leagues]
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return sorted.take(_maxLeaguesScanned).toList(growable: false);
  }

  /// The first league (most recently updated first) where the viewer has
  /// their own team, with their live position/points in that table.
  /// Returns null when the viewer has no team anywhere yet -- never a
  /// fabricated placeholder row.
  Future<HomeStandingsSummary?> loadFeaturedStandings(String uid) async {
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) return null;

    for (final league in await _recentLeagues()) {
      try {
        final teams = await _leaguesRepo.getTeams(league.id);
        if (!teams.any((t) => t.id == trimmedUid)) continue;

        final matches = await _leaguesRepo.getMatches(league.id);
        final rows = StandingsCalculator.calculate(
          teams: teams,
          matches: matches,
        );
        final idx = rows.indexWhere((r) => r.teamId == trimmedUid);
        if (idx < 0) continue;

        return HomeStandingsSummary(
          league: league,
          position: idx + 1,
          totalTeams: rows.length,
          played: rows[idx].mp,
          points: rows[idx].pts,
        );
      } catch (_) {
        // Skip a league we couldn't read and keep scanning the rest.
      }
    }
    return null;
  }

  int _highlightTimestampMs(MatchHighlight h) =>
      h.createdAt?.millisecondsSinceEpoch ?? 0;

  /// The single most recent APPROVED highlight across the user's leagues.
  Future<HomeLatestHighlight?> loadLatestHighlight() async {
    MatchHighlight? best;
    League? bestLeague;

    for (final league in await _recentLeagues()) {
      try {
        final list = await _highlightsRepo
            .watchLeagueHighlights(leagueId: league.id, limit: 5)
            .first
            .timeout(const Duration(seconds: 8));

        for (final h in list) {
          if (!h.isApproved) continue;
          if (best == null ||
              _highlightTimestampMs(h) > _highlightTimestampMs(best)) {
            best = h;
            bestLeague = league;
          }
        }
      } catch (_) {
        // Skip a league whose highlights feed errored/timed out.
      }
    }

    if (best == null || bestLeague == null) return null;
    return HomeLatestHighlight(league: bestLeague, highlight: best);
  }

  /// The nearest not-yet-played fixtures across the user's leagues, in
  /// each league's own round/sort order (no fabricated kickoff times --
  /// this app's fixtures don't carry a scheduled-at field today).
  Future<List<HomeUpcomingFixture>> loadUpcomingFixtures({
    int limit = 4,
  }) async {
    final result = <HomeUpcomingFixture>[];

    for (final league in await _recentLeagues()) {
      if (result.length >= limit) break;
      try {
        final matches = await _leaguesRepo.getMatches(league.id);
        final scheduled = matches
            .where((m) => m.status == MatchStatus.scheduled)
            .toList()
          ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
        if (scheduled.isEmpty) continue;

        final teams = await _leaguesRepo.getTeams(league.id);
        final teamsById = {for (final t in teams) t.id: t};

        for (final m in scheduled) {
          if (result.length >= limit) break;
          final home = teamsById[m.homeTeamId];
          final away = teamsById[m.awayTeamId];
          if (home == null || away == null) continue;
          result.add(HomeUpcomingFixture(
            league: league,
            match: m,
            homeTeam: home,
            awayTeam: away,
          ));
        }
      } catch (_) {
        // Skip a league we couldn't read and keep scanning the rest.
      }
    }

    return result;
  }
}
