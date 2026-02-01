import '../../models/fixture_match.dart';
import '../../models/team.dart';
import 'standings.dart';

/// Computes league/group tables from played matches.
///
/// IMPORTANT INVARIANT:
/// - Only matches where [FixtureMatch.isPlayed] is true are counted.
///   (Your FixtureMatch.isPlayed must guarantee scores are non-null.)
///
/// Tie-breakers applied (deterministic):
/// 1) Points (descending)
/// 2) Head-to-head points (descending) between the tied teams
/// 3) Goal Difference (descending)
/// 4) Goals For (descending)
/// 5) TeamId (ascending) as stable final fallback
///
/// Note:
/// - Head-to-head is points-only (no H2H goal difference mini-league).
class StandingsCalculator {
  static List<StandingsRow> calculate({
    required List<Team> teams,
    required List<FixtureMatch> matches,
  }) {
    final rows = <String, StandingsRow>{
      for (final t in teams) t.id: StandingsRow.empty(teamId: t.id, teamName: t.name),
    };

    // Update rows from played matches
    for (final m in matches) {
      if (!m.isPlayed) continue;

      final home = rows[m.homeTeamId];
      final away = rows[m.awayTeamId];
      if (home == null || away == null) continue;

      final hs = m.homeScore!;
      final as = m.awayScore!;

      var h = home.copyWith(mp: home.mp + 1, gf: home.gf + hs, ga: home.ga + as);
      var a = away.copyWith(mp: away.mp + 1, gf: away.gf + as, ga: away.ga + hs);

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

    final list = rows.values.toList();

    int headToHeadCompare(String aTeamId, String bTeamId) {
      int aPoints = 0;
      int bPoints = 0;

      for (final m in matches) {
        if (!m.isPlayed) continue;

        final isRelevant =
            (m.homeTeamId == aTeamId && m.awayTeamId == bTeamId) ||
            (m.homeTeamId == bTeamId && m.awayTeamId == aTeamId);

        if (!isRelevant) continue;

        final homeGoals = m.homeScore!;
        final awayGoals = m.awayScore!;

        if (homeGoals == awayGoals) {
          aPoints += 1;
          bPoints += 1;
        } else if (homeGoals > awayGoals) {
          if (m.homeTeamId == aTeamId) {
            aPoints += 3;
          } else {
            bPoints += 3;
          }
        } else {
          if (m.awayTeamId == aTeamId) {
            aPoints += 3;
          } else {
            bPoints += 3;
          }
        }
      }

      return bPoints.compareTo(aPoints);
    }

    list.sort((a, b) {
      final pts = b.pts.compareTo(a.pts);
      if (pts != 0) return pts;

      final h2h = headToHeadCompare(a.teamId, b.teamId);
      if (h2h != 0) return h2h;

      final gd = b.gd.compareTo(a.gd);
      if (gd != 0) return gd;

      final gf = b.gf.compareTo(a.gf);
      if (gf != 0) return gf;

      // Stable deterministic fallback (must match StandingsEngine fallback)
      return a.teamId.compareTo(b.teamId);
    });

    return list;
  }
}
