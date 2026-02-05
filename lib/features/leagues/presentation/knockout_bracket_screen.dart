import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/leagues_repository_local.dart';
import '../models/enums.dart';
import '../models/knockout_match.dart';
import '../models/team.dart';

class KnockoutBracketScreen extends ConsumerStatefulWidget {
  final String leagueId;

  const KnockoutBracketScreen({
    super.key,
    required this.leagueId,
  });

  @override
  ConsumerState<KnockoutBracketScreen> createState() => _KnockoutBracketScreenState();
}

class _KnockoutBracketScreenState extends ConsumerState<KnockoutBracketScreen> {
  late LocalLeaguesRepository _repo;
  bool _isLoading = true;
  List<KnockoutMatch> _matches = [];
  Map<String, Team> _teamsById = {};

  static const _roundOrder = <String>[
    'Play-off',
    'Round of 16',
    'Quarter Finals',
    'Semi Finals',
    'Final',
    '3rd Place',
  ];

  @override
  void initState() {
    super.initState();
    _repo = LocalLeaguesRepository(ref.read(prefsServiceProvider));
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final teams = await _repo.getTeams(widget.leagueId);
    final koMatches = await _repo.getKnockoutMatches(widget.leagueId);

    if (!mounted) return;
    setState(() {
      _teamsById = {for (final t in teams) t.id: t};
      _matches = koMatches;
      _isLoading = false;
    });
  }

  String _roundDisplayName(String roundName) {
    final l10n = context.l10n;
    switch (roundName) {
      case 'Play-off':
        return l10n.tr('admin_knockout_round_playoff');
      case 'Round of 16':
        return l10n.tr('admin_knockout_round_r16');
      case 'Quarter Finals':
        return l10n.tr('admin_knockout_round_quarter_finals');
      case 'Semi Finals':
        return l10n.tr('admin_knockout_round_semi_finals');
      case 'Final':
        return l10n.tr('admin_knockout_round_final');
      case '3rd Place':
        return l10n.tr('admin_knockout_round_third_place');
      default:
        return roundName;
    }
  }

  String _pairKey(String a, String b) => (a.compareTo(b) < 0) ? '$a|$b' : '$b|$a';

  bool _isFinished(KnockoutMatch m) {
    final done = (m.status == MatchStatus.played || m.status == MatchStatus.completed);
    return done && m.homeScore != null && m.awayScore != null;
  }

  KnockoutMatch? _findOtherLeg(KnockoutMatch m) {
    if (m.roundName != 'Play-off') return null;
    final a = m.homeTeamId;
    final b = m.awayTeamId;
    if (a == null || b == null) return null;
    final next = m.nextMatchId;
    if (next == null) return null;

    final key = _pairKey(a, b);

    for (final x in _matches) {
      if (x.id == m.id) continue;
      if (x.roundName != 'Play-off') continue;
      if (x.nextMatchId != next) continue;
      final xa = x.homeTeamId;
      final xb = x.awayTeamId;
      if (xa == null || xb == null) continue;
      if (_pairKey(xa, xb) != key) continue;
      return x;
    }
    return null;
  }

  String? _aggregateWinner(KnockoutMatch leg) {
    if (leg.roundName != 'Play-off') return null;

    final other = _findOtherLeg(leg);
    if (other == null) return null;

    final a1 = leg.homeTeamId;
    final b1 = leg.awayTeamId;
    if (a1 == null || b1 == null) return null;

    if (!_isFinished(leg) || !_isFinished(other)) return null;

    final totals = <String, int>{};

    void add(KnockoutMatch m) {
      final h = m.homeTeamId!;
      final a = m.awayTeamId!;
      totals[h] = (totals[h] ?? 0) + m.homeScore!;
      totals[a] = (totals[a] ?? 0) + m.awayScore!;
    }

    add(leg);
    add(other);

    final aTot = totals[a1] ?? 0;
    final bTot = totals[b1] ?? 0;

    if (aTot > bTot) return a1;
    if (bTot > aTot) return b1;

    // Aggregate tie: winner must be set on second leg.
    final second = leg.isSecondLeg ? leg : (other.isSecondLeg ? other : null);
    return second?.tiebreakWinnerTeamId;
  }

  String? _teamName(String? id) {
    if (id == null) return null;
    return _teamsById[id]?.name ?? id;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final appBarFg = Theme.of(context).appBarTheme.foregroundColor ?? Theme.of(context).colorScheme.onBackground;

    final rounds = <String, List<KnockoutMatch>>{};
    for (var m in _matches) {
      rounds.putIfAbsent(m.roundName, () => []).add(m);
    }

    final roundNames = rounds.keys.toList()
      ..sort((a, b) {
        final ai = _roundOrder.indexOf(a);
        final bi = _roundOrder.indexOf(b);
        if (ai == -1 && bi == -1) return a.compareTo(b);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });

    // Stable ordering inside each round (especially Play-off).
    for (final rn in roundNames) {
      final list = rounds[rn]!;
      list.sort((a, b) {
        final an = (a.nextMatchId ?? '');
        final bn = (b.nextMatchId ?? '');
        final c1 = an.compareTo(bn);
        if (c1 != 0) return c1;

        final c2 = (a.isSecondLeg ? 1 : 0).compareTo(b.isSecondLeg ? 1 : 0);
        if (c2 != 0) return c2;

        return a.id.compareTo(b.id);
      });
    }

    return GlassScaffold(
      appBar: AppBar(
        title: Text(
          l10n.tr('knockout_bracket_appbar_title'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: appBarFg.withOpacity(0.92),
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.sync_rounded, color: Colors.cyanAccent),
            tooltip: l10n.tr('knockout_bracket_reload_tooltip'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _matches.isEmpty
                  ? Center(
                      child: Glass(
                        padding: const EdgeInsets.all(32),
                        borderRadius: 24,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.emoji_events_outlined, size: 48, color: Colors.white24),
                            const SizedBox(height: 16),
                            Text(
                              l10n.tr('knockout_bracket_empty_state'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        const SizedBox(height: 10),
                        _buildHeaderInfo(),
                        const SizedBox(height: 16),
                        Expanded(
                          child: InteractiveViewer(
                            constrained: false,
                            boundaryMargin: const EdgeInsets.all(150),
                            minScale: 0.2,
                            maxScale: 2.0,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var i = 0; i < roundNames.length; i++) ...[
                                    _buildRoundColumn(_roundDisplayName(roundNames[i]), rounds[roundNames[i]]!),
                                    if (i < roundNames.length - 1) _buildBracketConnector(),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }

  Widget _buildHeaderInfo() {
    final l10n = context.l10n;

    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          Glass(
            borderRadius: 18,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.tr('knockout_bracket_header_title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  '${_matches.length} ${l10n.tr('knockout_bracket_matches_scheduled_suffix')}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          PositionedDirectional(
            top: 0,
            bottom: 0,
            start: 0,
            child: Container(
              width: 3,
              decoration: const BoxDecoration(
                color: Colors.cyanAccent,
                borderRadius: BorderRadiusDirectional.only(
                  topStart: Radius.circular(18),
                  bottomStart: Radius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundColumn(String title, List<KnockoutMatch> roundMatches) {
    return Column(
      children: [
        SizedBox(
          width: 240,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Glass(
              borderRadius: 30,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Text(
                title.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ),
        ...roundMatches.map(_buildMatchCard).toList(),
      ],
    );
  }

  Widget _buildMatchCard(KnockoutMatch match) {
    final l10n = context.l10n;

    final homeName = _teamName(match.homeTeamId) ?? (match.homeTeamId ?? l10n.tr('fixtures_tbd'));
    final awayName = _teamName(match.awayTeamId) ?? (match.awayTeamId ?? l10n.tr('fixtures_tbd'));

    final isTBD = match.homeTeamId == null || match.awayTeamId == null;

    bool isHomeWinner = false;
    bool isAwayWinner = false;

    String? subtitle;
    String? aggNote;
    String? tiebreakNote;

    if (match.roundName == 'Play-off') {
      subtitle = match.isSecondLeg ? l10n.tr('admin_knockout_leg2') : l10n.tr('admin_knockout_leg1');

      final other = _findOtherLeg(match);
      if (other != null && _isFinished(match) && _isFinished(other)) {
        final winner = _aggregateWinner(match);
        if (winner != null) {
          isHomeWinner = (winner == match.homeTeamId);
          isAwayWinner = (winner == match.awayTeamId);
        } else {
          tiebreakNote = l10n.tr('knockout_bracket_aggregate_tied_penalties_required');
        }

        final hId = match.homeTeamId!;
        final aId = match.awayTeamId!;
        final totals = <String, int>{};

        void add(KnockoutMatch m) {
          totals[m.homeTeamId!] = (totals[m.homeTeamId!] ?? 0) + m.homeScore!;
          totals[m.awayTeamId!] = (totals[m.awayTeamId!] ?? 0) + m.awayScore!;
        }

        add(match);
        add(other);

        final hAgg = totals[hId] ?? 0;
        final aAgg = totals[aId] ?? 0;
        aggNote = '${l10n.tr('knockout_bracket_aggregate_prefix')}$hAgg - $aAgg';

        if (hAgg == aAgg) {
          final second = match.isSecondLeg ? match : (other.isSecondLeg ? other : null);
          if (second?.tiebreakWinnerTeamId != null) {
            tiebreakNote =
                '${l10n.tr('knockout_bracket_penalties_prefix')}${_teamName(second!.tiebreakWinnerTeamId) ?? second.tiebreakWinnerTeamId}';
          }
        }
      }
    } else {
      if (_isFinished(match)) {
        if (match.homeScore! > match.awayScore!) {
          isHomeWinner = true;
        } else if (match.awayScore! > match.homeScore!) {
          isAwayWinner = true;
        } else if (match.tiebreakWinnerTeamId != null) {
          isHomeWinner = match.tiebreakWinnerTeamId == match.homeTeamId;
          isAwayWinner = match.tiebreakWinnerTeamId == match.awayTeamId;
          tiebreakNote =
              '${l10n.tr('knockout_bracket_penalties_prefix')}${_teamName(match.tiebreakWinnerTeamId) ?? match.tiebreakWinnerTeamId}';
        } else {
          // Should no longer happen if admin screen enforces penalties winner.
          tiebreakNote = l10n.tr('knockout_bracket_draw_winner_required');
        }
      }
    }

    return Container(
      width: 240,
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      child: Stack(
        children: [
          Glass(
            borderRadius: 12,
            padding: const EdgeInsets.all(1),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                gradient: LinearGradient(
                  colors: [
                    isTBD ? Colors.white10 : Colors.cyanAccent.withOpacity(0.1),
                    Colors.transparent,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    if (subtitle != null)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (subtitle != null) const SizedBox(height: 8),
                    _buildTeamRow(homeName, match.homeScore?.toString() ?? "-", isHomeWinner),
                    const SizedBox(height: 8),
                    Divider(color: Colors.white.withOpacity(0.05), height: 1),
                    const SizedBox(height: 8),
                    _buildTeamRow(awayName, match.awayScore?.toString() ?? "-", isAwayWinner),
                    if (aggNote != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          aggNote!,
                          style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    if (tiebreakNote != null) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          tiebreakNote!,
                          style: TextStyle(
                            color: tiebreakNote == l10n.tr('knockout_bracket_draw_winner_required')
                                ? Colors.orangeAccent
                                : Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 0,
            bottom: 0,
            start: 0,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: isTBD ? Colors.white24 : Colors.cyanAccent,
                borderRadius: const BorderRadiusDirectional.only(
                  topStart: Radius.circular(12),
                  bottomStart: Radius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamRow(String name, String score, bool isWinner) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isWinner ? Colors.cyanAccent : (score == "-" ? Colors.white38 : Colors.white),
              fontSize: 13,
              fontWeight: isWinner ? FontWeight.w900 : FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isWinner ? Colors.cyanAccent.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            score,
            style: TextStyle(
              color: isWinner ? Colors.cyanAccent : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBracketConnector() {
    return Container(
      width: 40,
      margin: const EdgeInsets.only(top: 100),
      child: Center(
        child: Container(
          height: 1,
          width: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.cyanAccent.withOpacity(0.5),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
