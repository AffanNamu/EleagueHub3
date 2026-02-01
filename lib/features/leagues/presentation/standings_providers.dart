import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/prefs_service.dart';
import '../data/leagues_repository_local.dart';
import '../domain/standings/standings.dart';
import '../domain/standings/standings_calculator.dart';
import '../models/league.dart';
import '../models/league_format.dart';

/// Provides a single instance of [LocalLeaguesRepository] using the shared
/// [PreferencesService].
final localLeaguesRepositoryProvider = Provider<LocalLeaguesRepository>((ref) {
  final prefs = ref.watch(prefsServiceProvider);
  return LocalLeaguesRepository(prefs);
});

/// Loads a League by ID (to access format, settings, etc.).
final leagueProvider = FutureProvider.family<League, String>(
  (ref, leagueId) async {
    final repo = ref.watch(localLeaguesRepositoryProvider);
    final league = await repo.getLeagueById(leagueId);
    if (league == null) {
      throw Exception('League not found');
    }
    return league;
  },
);

/// Computes GLOBAL league standings for a given league ID by:
/// - Loading all teams + all matches from local storage
/// - Running [StandingsCalculator.calculate] over them
///
/// Used for:
/// - Classic leagues
/// - Swiss leagues (single-table view)
final leagueStandingsProvider = FutureProvider.family<List<StandingsRow>, String>(
  (ref, leagueId) async {
    final repo = ref.watch(localLeaguesRepositoryProvider);

    final league = await repo.getLeagueById(leagueId);
    final teams = await repo.getTeams(leagueId);
    final matches = await repo.getMatches(leagueId);

    // IMPORTANT:
    // - Swiss standings must only consider Swiss league-phase matches (groupId == null).
    // - Classic typically also has groupId == null.
    final filteredMatches = (league?.format == LeagueFormat.uclSwiss)
        ? matches.where((m) => m.groupId == null).toList()
        : matches;

    return StandingsCalculator.calculate(
      teams: teams,
      matches: filteredMatches,
    );
  },
);

/// Computes GROUPED standings for UCL-style group stages.
///
/// Returns:
///   groupId -> List<StandingsRow> (including teams with 0 matches)
///
/// Source-of-truth for groups:
/// - Team.groupId (NOT matches), so tables exist even before any match is played.
final leagueGroupedStandingsProvider =
    FutureProvider.family<Map<String, List<StandingsRow>>, String>(
  (ref, leagueId) async {
    final repo = ref.watch(localLeaguesRepositoryProvider);

    final allTeams = await repo.getTeams(leagueId);
    final allMatches = await repo.getMatches(leagueId);

    // Group IDs come from team assignments.
    final groupIds = allTeams
        .map((t) => t.groupId)
        .whereType<String>()
        .map((g) => g.trim())
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final result = <String, List<StandingsRow>>{};

    for (final groupId in groupIds) {
      final groupTeams = allTeams.where((t) => (t.groupId ?? '').trim() == groupId).toList();
      if (groupTeams.isEmpty) continue;

      final groupMatches = allMatches.where((m) => (m.groupId ?? '').trim() == groupId).toList();

      // StandingsCalculator will include all teams (even MP=0) because we pass groupTeams.
      final standings = StandingsCalculator.calculate(
        teams: groupTeams,
        matches: groupMatches,
      );

      result[groupId] = standings;
    }

    return result;
  },
);
