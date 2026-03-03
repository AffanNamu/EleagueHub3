import '../../models/fixture_match.dart';
import '../../models/team.dart';
import 'standings.dart';

/// Computes league/group tables from played matches and applies admin adjustments.
///
/// IMPORTANT INVARIANT:
/// - Only matches where [FixtureMatch.isPlayed] is true are counted.
///   (Your FixtureMatch.isPlayed must guarantee scores are non-null.)
///
/// STANDINGS RULE (production requirement):
/// Sorting priority:
/// 1) finalPoints DESC  (base points + adminAdjustment)
/// 2) goalDifference DESC
/// 3) goalsFor DESC
/// 4) teamId ASC (stable deterministic fallback)
///
/// NOTE:
/// - Historical head-to-head tie-break logic is intentionally disabled to match
///   the required production rule. The helper remains for reference and to allow
///   future feature-flag reintroduction without rewriting it.
class StandingsCalculator {
  // Keep for potential future use; requirement currently does NOT use H2H.
  static const bool _useHeadToHeadTieBreaker = false;

  static List<StandingsRow> calculate({
    required List<Team> teams,
    required List<FixtureMatch> matches,
    Map<String, int> adminAdjustmentsByTeamId = const <String, int>{},
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

    final list = rows.values.toList(growable: false);

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
      // 1) finalPoints DESC
      final fp = b.finalPoints.compareTo(a.finalPoints);
      if (fp != 0) return fp;

      // (Disabled per requirements; left for future reintroduction)
      if (_useHeadToHeadTieBreaker) {
        final h2h = headToHeadCompare(a.teamId, b.teamId);
        if (h2h != 0) return h2h;
      }

      // 2) Goal Difference DESC
      final gd = b.gd.compareTo(a.gd);
      if (gd != 0) return gd;

      // 3) Goals For DESC
      final gf = b.gf.compareTo(a.gf);
      if (gf != 0) return gf;

      // 4) Stable deterministic fallback
      return a.teamId.compareTo(b.teamId);
    });

    return list;
  }
}
