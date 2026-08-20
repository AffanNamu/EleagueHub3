//standings providers
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/prefs_service.dart';
import '../data/leagues_repository_local.dart';
import '../domain/standings/standings.dart';
import '../domain/standings/standings_calculator.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../models/point_adjustment.dart';

/// Provides a single instance of [LocalLeaguesRepository].
///
/// ONLINE-ONLY NOTE:
/// - Despite the legacy name, LocalLeaguesRepository is Firestore-backed in this migration.
/// - PreferencesService is passed only because older constructors/providers expect it.
final localLeaguesRepositoryProvider = Provider<LocalLeaguesRepository>((ref) {
  final prefs = ref.watch(prefsServiceProvider);
  return LocalLeaguesRepository(prefs);
});

/// Loads a League by ID (format, settings, etc.).
final leagueProvider = FutureProvider.family<League, String>(
  (ref, leagueId) async {
    final repo = ref.watch(localLeaguesRepositoryProvider);
    final league = await repo.getLeagueById(leagueId).timeout(const Duration(seconds: 20));
    if (league == null) {
      throw Exception('League not found.');
    }
    return league;
  },
);

Stream<R> _combineLatest3<A, B, C, R>({
  required Stream<A> a,
  required Stream<B> b,
  required Stream<C> c,
  required R Function(A, B, C) combiner,
}) {
  late final StreamController<R> controller;

  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  StreamSubscription<C>? subC;

  A? lastA;
  B? lastB;
  C? lastC;

  var hasA = false;
  var hasB = false;
  var hasC = false;

  var doneCount = 0;

  void emitIfReady() {
    if (!controller.isClosed && hasA && hasB && hasC) {
      controller.add(combiner(lastA as A, lastB as B, lastC as C));
    }
  }

  void markDone() {
    doneCount += 1;
    if (!controller.isClosed && doneCount >= 3) {
      controller.close();
    }
  }

  controller = StreamController<R>(
    onListen: () {
      subA = a.listen((value) {
        lastA = value;
        hasA = true;
        emitIfReady();
      }, onError: controller.addError, onDone: markDone);

      subB = b.listen((value) {
        lastB = value;
        hasB = true;
        emitIfReady();
      }, onError: controller.addError, onDone: markDone);

      subC = c.listen((value) {
        lastC = value;
        hasC = true;
        emitIfReady();
      }, onError: controller.addError, onDone: markDone);
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
      await subC?.cancel();
    },
  );

  return controller.stream;
}

/// Real-time GLOBAL league standings for a given league ID by:
/// - Listening to teams + matches via Firestore snapshot listeners
/// - Applying adminAdjustment from team documents (scalable)
/// - Running [StandingsCalculator.calculate] for base stats
///
/// WHY THIS IS SCALABLE:
/// - Standings do NOT need to stream the entire pointAdjustments audit log.
/// - Each adjustment transaction updates the team aggregate field (adminAdjustment).
final leagueStandingsProvider = StreamProvider.family<List<StandingsRow>, String>(
  (ref, leagueId) async* {
    final repo = ref.watch(localLeaguesRepositoryProvider);

    // League format is fetched once; format changes are rare and not critical for standings order.
    final league = await repo.getLeagueById(leagueId).timeout(const Duration(seconds: 20));

    final teams$ = repo.watchTeams(leagueId);
    final matches$ = repo.watchMatches(leagueId);
    final adminAdj$ = repo.watchTeamAdminAdjustmentsByTeamId(leagueId);

    final combined$ = _combineLatest3(
      a: teams$,
      b: matches$,
      c: adminAdj$,
      combiner: (teams, matches, adminAdjByTeamId) {
        final filteredMatches = (league?.format == LeagueFormat.uclSwiss)
            ? matches.where((m) => m.groupId == null).toList(growable: false)
            : matches;

        return StandingsCalculator.calculate(
          teams: teams,
          matches: filteredMatches,
          adminAdjustmentsByTeamId: adminAdjByTeamId,
        );
      },
    );

    yield* combined$;
  },
);

/// Real-time GROUPED standings for UCL-style group stages.
///
/// Returns:
///   groupId -> List<StandingsRow> (including teams with 0 matches)
///
/// Source-of-truth for groups:
/// - Team.groupId (NOT matches), so tables exist even before any match is played.
final leagueGroupedStandingsProvider = StreamProvider.family<Map<String, List<StandingsRow>>, String>(
  (ref, leagueId) async* {
    final repo = ref.watch(localLeaguesRepositoryProvider);

    final teams$ = repo.watchTeams(leagueId);
    final matches$ = repo.watchMatches(leagueId);
    final adminAdj$ = repo.watchTeamAdminAdjustmentsByTeamId(leagueId);

    final combined$ = _combineLatest3(
      a: teams$,
      b: matches$,
      c: adminAdj$,
      combiner: (allTeams, allMatches, adminAdjByTeamId) {
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
          final groupTeams = allTeams.where((t) => (t.groupId ?? '').trim() == groupId).toList(growable: false);
          if (groupTeams.isEmpty) continue;

          final groupMatches = allMatches.where((m) => (m.groupId ?? '').trim() == groupId).toList(growable: false);

          final standings = StandingsCalculator.calculate(
            teams: groupTeams,
            matches: groupMatches,
            adminAdjustmentsByTeamId: adminAdjByTeamId,
          );

          result[groupId] = standings;
        }

        return result;
      },
    );

    yield* combined$;
  },
);

/// Real-time audit log stream for admin point adjustments (UI can render this).
///
/// NOTE:
/// - This stream is intended for admin/audit screens.
/// - Standings should rely on team aggregate fields for scale.
final leaguePointAdjustmentsProvider = StreamProvider.family<List<PointAdjustment>, String>((ref, leagueId) {
  final repo = ref.watch(localLeaguesRepositoryProvider);
  return repo.watchPointAdjustments(leagueId: leagueId, limit: 200);
});
