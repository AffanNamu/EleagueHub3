import '../../models/fixture_match.dart';
import '../../models/team.dart';
import 'standings.dart';

/// Computes league/group tables from played matches and applies admin adjustments.
///
/// IMPORTANT INVARIANT:
/// - Only matches where [FixtureMatch.isPlayed] is true are counted.
///
/// DEFAULT STANDINGS RULE (unchanged):
/// Sorting priority:
/// 1) finalPoints DESC  (base points + adminAdjustment)
/// 2) goalDifference DESC
/// 3) goalsFor DESC
/// 4) teamId ASC (stable deterministic fallback)
///
/// WORLD CUP (FIFA) TIE-BREAKERS (optional):
/// When [fifaGroupTieBreakers] is true, after applying the default ordering,
/// we resolve ties on (finalPoints, gd, gf) using FIFA-style head-to-head
/// among the tied teams:
///   - head-to-head points DESC
///   - head-to-head goal difference DESC
///   - head-to-head goals for DESC
///   - teamId ASC (stable deterministic fallback)
///
/// Notes:
/// - Fair Play / drawing lots are not supported in the current data model.
///   We fall back deterministically to teamId ASC.
/// - This tie-break applies ONLY within the tied cluster; it does not affect
///   teams outside the cluster.
class StandingsCalculator {
  static List<StandingsRow> calculate({
    required List<Team> teams,
    required List<FixtureMatch> matches,
    Map<String, int> adminAdjustmentsByTeamId = const <String, int>{},

    /// When true, apply FIFA-style head-to-head tie-breaking for clusters
    /// that remain tied after points/gd/gf.
    ///
    /// Keep default false to avoid changing behavior for existing league types.
    bool fifaGroupTieBreakers = false,
  }) {
    final rows = <String, StandingsRow>{
      for (final t in teams)
        t.id: StandingsRow.empty(
          teamId: t.id,
          teamName: t.name,
          adminAdjustment: adminAdjustmentsByTeamId[t.id] ?? 0,
        ),
    };

    // Update rows from played matches
    for (final m in matches) {
      if (!m.isPlayed) continue;

      final home = rows[m.homeTeamId];
      final away = rows[m.awayTeamId];
      if (home == null || away == null) continue;

      final hs = m.homeScore!;
      final as = m.awayScore!;

      var h = home.copyWith(
        mp: home.mp + 1,
        gf: home.gf + hs,
        ga: home.ga + as,
      );
      var a = away.copyWith(
        mp: away.mp + 1,
        gf: away.gf + as,
        ga: away.ga + hs,
      );

      if (hs > as) {
        h = h.copyWith(w: h.w + 1);
        a = a.copyWith(l: a.l + 1);
      } else if (hs < as) {
        h = h.copyWith(l: h.l + 1);
        a = a.copyWith(w: a.w + 1);
      } else {
        h = h.copyWith(d: h.d + 1);
        a = a.copyWith(d: a.d + 1);
      }

      rows[m.homeTeamId] = h;
      rows[m.awayTeamId] = a;
    }

    final list = rows.values.toList(growable: false);

    // Default ordering (production rule)
    list.sort(_baseCompare);

    // Optional FIFA tie-break (World Cup groups).
    if (!fifaGroupTieBreakers) return list;

    return _applyFifaHeadToHeadTieBreakers(
      sortedByBaseRules: list,
      matches: matches,
    );
  }

  static int _baseCompare(StandingsRow a, StandingsRow b) {
    // 1) finalPoints DESC
    final fp = b.finalPoints.compareTo(a.finalPoints);
    if (fp != 0) return fp;

    // 2) Goal Difference DESC
    final gd = b.gd.compareTo(a.gd);
    if (gd != 0) return gd;

    // 3) Goals For DESC
    final gf = b.gf.compareTo(a.gf);
    if (gf != 0) return gf;

    // 4) Stable deterministic fallback
    return a.teamId.compareTo(b.teamId);
  }

  static bool _samePrimaryClusterKey(StandingsRow a, StandingsRow b) {
    return a.finalPoints == b.finalPoints && a.gd == b.gd && a.gf == b.gf;
  }

  static List<StandingsRow> _applyFifaHeadToHeadTieBreakers({
    required List<StandingsRow> sortedByBaseRules,
    required List<FixtureMatch> matches,
  }) {
    final out = <StandingsRow>[];

    int i = 0;
    while (i < sortedByBaseRules.length) {
      int j = i + 1;
      while (j < sortedByBaseRules.length &&
          _samePrimaryClusterKey(sortedByBaseRules[i], sortedByBaseRules[j])) {
        j++;
      }

      // Single team (no tie)
      if (j - i <= 1) {
        out.add(sortedByBaseRules[i]);
        i = j;
        continue;
      }

      // Tie cluster: apply FIFA head-to-head among the tied teams
      final cluster = sortedByBaseRules.sublist(i, j);
      out.addAll(_resolveClusterByHeadToHead(cluster: cluster, matches: matches));

      i = j;
    }

    return out;
  }

  static List<StandingsRow> _resolveClusterByHeadToHead({
    required List<StandingsRow> cluster,
    required List<FixtureMatch> matches,
  }) {
    final ids = cluster.map((e) => e.teamId).toSet();

    final h2h = <String, _H2HStats>{
      for (final id in ids) id: const _H2HStats(),
    };

    for (final m in matches) {
      if (!m.isPlayed) continue;

      final homeId = m.homeTeamId;
      final awayId = m.awayTeamId;

      if (!ids.contains(homeId) || !ids.contains(awayId)) continue;

      final hs = m.homeScore!;
      final as = m.awayScore!;

      // goals
      h2h[homeId] = h2h[homeId]!.add(gf: hs, ga: as);
      h2h[awayId] = h2h[awayId]!.add(gf: as, ga: hs);

      // points
      if (hs > as) {
        h2h[homeId] = h2h[homeId]!.add(points: 3);
      } else if (hs < as) {
        h2h[awayId] = h2h[awayId]!.add(points: 3);
      } else {
        h2h[homeId] = h2h[homeId]!.add(points: 1);
        h2h[awayId] = h2h[awayId]!.add(points: 1);
      }
    }

    final sorted = cluster.toList(growable: false)
      ..sort((a, b) {
        final sa = h2h[a.teamId]!;
        final sb = h2h[b.teamId]!;

        // FIFA head-to-head criteria (for the tied cluster)
        final p = sb.points.compareTo(sa.points);
        if (p != 0) return p;

        final gd = sb.gd.compareTo(sa.gd);
        if (gd != 0) return gd;

        final gf = sb.gf.compareTo(sa.gf);
        if (gf != 0) return gf;

        // Deterministic fallback (Fair play not supported)
        return a.teamId.compareTo(b.teamId);
      });

    return sorted;
  }
}

/// Internal value object for head-to-head stats inside a tie cluster.
class _H2HStats {
  final int points;
  final int gf;
  final int ga;

  const _H2HStats({
    this.points = 0,
    this.gf = 0,
    this.ga = 0,
  });

  int get gd => gf - ga;

  _H2HStats add({
    int points = 0,
    int gf = 0,
    int ga = 0,
  }) {
    return _H2HStats(
      points: this.points + points,
      gf: this.gf + gf,
      ga: this.ga + ga,
    );
  }
}