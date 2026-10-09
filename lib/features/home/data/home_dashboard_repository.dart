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

/// Bundles the standings + fixtures sections from one shared scan of the
/// user's recent leagues (both need the same per-league teams/matches, so
/// they're loaded together). Highlights are loaded as a separate, independent
/// future -- see [HomeDashboardRepository.loadLatestHighlight] -- so a slow
/// or timed-out highlights scan never blocks these two from rendering.
class HomeStructuralDashboardData {
  const HomeStructuralDashboardData({
    required this.standings,
    required this.fixtures,
  });

  final HomeStandingsSummary? standings;
  final List<HomeUpcomingFixture> fixtures;
}

/// One league's teams + matches, fetched once and reused by both the
/// standings and fixtures sections (previously each fetched independently).
class _LeagueSnapshot {
  const _LeagueSnapshot({
    required this.league,
    required this.teams,
    required this.matches,
  });

  final League league;
  final List<Team> teams;
  final List<FixtureMatch> matches;
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

  /// Fetches each recent league's teams + matches exactly once, so the
  /// standings and fixtures sections below don't each re-fetch the same
  /// per-league data. Leagues that fail to load are skipped (same
  /// best-effort behavior the individual loaders used to have).
  Future<List<_LeagueSnapshot>> _loadLeagueSnapshots(
    List<League> leagues,
  ) async {
    final snapshots = await Future.wait(leagues.map((league) async {
      try {
        final teams = await _leaguesRepo.getTeams(league.id);
        final matches = await _leaguesRepo.getMatches(league.id);
        return _LeagueSnapshot(
          league: league,
          teams: teams,
          matches: matches,
        );
      } catch (_) {
        return null;
      }
    }));
    return snapshots.whereType<_LeagueSnapshot>().toList(growable: false);
  }

  HomeStandingsSummary? _featuredStandingsFrom(
    List<_LeagueSnapshot> snapshots,
    String uid,
  ) {
    for (final snap in snapshots) {
      if (!snap.teams.any((t) => t.id == uid)) continue;

      final rows = StandingsCalculator.calculate(
        teams: snap.teams,
        matches: snap.matches,
      );
      final idx = rows.indexWhere((r) => r.teamId == uid);
      if (idx < 0) continue;

      return HomeStandingsSummary(
        league: snap.league,
        position: idx + 1,
        totalTeams: rows.length,
        played: rows[idx].mp,
        points: rows[idx].pts,
      );
    }
    return null;
  }

  List<HomeUpcomingFixture> _upcomingFixturesFrom(
    List<_LeagueSnapshot> snapshots, {
    required int limit,
  }) {
    final result = <HomeUpcomingFixture>[];

    for (final snap in snapshots) {
      if (result.length >= limit) break;

      final scheduled = snap.matches
          .where((m) => m.status == MatchStatus.scheduled)
          .toList()
        ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));
      if (scheduled.isEmpty) continue;

      final teamsById = {for (final t in snap.teams) t.id: t};

      for (final m in scheduled) {
        if (result.length >= limit) break;
        final home = teamsById[m.homeTeamId];
        final away = teamsById[m.awayTeamId];
        if (home == null || away == null) continue;
        result.add(HomeUpcomingFixture(
          league: snap.league,
          match: m,
          homeTeam: home,
          awayTeam: away,
        ));
      }
    }

    return result;
  }

  int _highlightTimestampMs(MatchHighlight h) =>
      h.createdAt?.millisecondsSinceEpoch ?? 0;

  /// Loads the standings + fixtures sections from one shared scan of the
  /// user's recent leagues, instead of each section independently calling
  /// listLeagues() and re-fetching the same per-league teams/matches (the
  /// two previously did this work twice between them).
  Future<HomeStructuralDashboardData> loadStructural(
    String uid, {
    int fixturesLimit = 4,
  }) async {
    final trimmedUid = uid.trim();
    final leagues = await _recentLeagues();
    final snapshots = await _loadLeagueSnapshots(leagues);

    final standings = trimmedUid.isEmpty
        ? null
        : _featuredStandingsFrom(snapshots, trimmedUid);
    final fixtures = _upcomingFixturesFrom(snapshots, limit: fixturesLimit);

    return HomeStructuralDashboardData(
      standings: standings,
      fixtures: fixtures,
    );
  }

  /// The single most recent APPROVED highlight across the user's leagues.
  /// Kept as its own independent future (own listLeagues() call, like
  /// before) rather than folded into [loadStructural] -- each per-league
  /// highlights read has an 8s timeout, and bundling it in would make a
  /// slow/timed-out highlights scan block the standings/fixtures sections
  /// from rendering, which previously could show as soon as they were
  /// ready, independent of how long highlights took.
  Future<HomeLatestHighlight?> loadLatestHighlight() async {
    final leagues = await _recentLeagues();

    MatchHighlight? best;
    League? bestLeague;

    for (final league in leagues) {
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
}
