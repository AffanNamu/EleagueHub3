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

/// Bundles all 3 Home-tab dashboard sections from one shared scan of the
/// user's recent leagues, instead of each section independently re-fetching
/// the same league list and the same per-league teams/matches.
class HomeDashboardData {
  const HomeDashboardData({
    required this.standings,
    required this.highlight,
    required this.fixtures,
  });

  final HomeStandingsSummary? standings;
  final HomeLatestHighlight? highlight;
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

  /// The single most recent APPROVED highlight across the user's leagues.
  /// Highlights live in their own subcollection (no overlap with
  /// teams/matches), so this still scans per-league independently --
  /// but off the one shared [leagues] list rather than a second
  /// [_recentLeagues] call.
  Future<HomeLatestHighlight?> _latestHighlightFrom(
    List<League> leagues,
  ) async {
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

  /// Loads all 3 Home-tab dashboard sections from one shared scan of the
  /// user's recent leagues. Replaces 3 independent loaders that each used
  /// to call listLeagues() and re-fetch the same per-league teams/matches
  /// on every Home tab open.
  Future<HomeDashboardData> loadDashboard(
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
    final highlight = await _latestHighlightFrom(leagues);

    return HomeDashboardData(
      standings: standings,
      highlight: highlight,
      fixtures: fixtures,
    );
  }
}
