import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../widgets/bracket_painter.dart';
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

  // Premium bracket layout constants.
  static const double _colWidth = 240;
  static const double _centerWidth = 320;
  static const double _connectorWidth = 56;

  static const double _matchCardHeight = 132;
  static const double _baseGap = 22; // earliest-round vertical gap
  static const double _unit = _matchCardHeight + _baseGap;

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

    final second = leg.isSecondLeg ? leg : (other.isSecondLeg ? other : null);
    return second?.tiebreakWinnerTeamId;
  }

  String? _teamName(String? id) {
    if (id == null) return null;
    return _teamsById[id]?.name ?? id;
  }

  bool _isPowerOfTwo(int v) => v > 0 && (v & (v - 1)) == 0;

  int _roundIndexForCount({
    required int maxMatches,
    required int count,
  }) {
    if (count <= 0 || maxMatches <= 0) return 0;
    if (maxMatches % count != 0) return 0;

    final ratio = maxMatches ~/ count;
    if (!_isPowerOfTwo(ratio)) return 0;

    int r = 0;
    int x = ratio;
    while (x > 1) {
      x ~/= 2;
      r++;
    }
    return r;
  }

  double _centerY({
    required int maxMatches,
    required int count,
    required int index,
  }) {
    final r = _roundIndexForCount(maxMatches: maxMatches, count: count);
    final pow2 = 1 << r;

    final offset = ((pow2 - 1) / 2.0) * _unit;
    final step = pow2 * _unit;

    return (_matchCardHeight / 2.0) + offset + index * step;
  }

  double _totalHeightForMaxMatches(int maxMatches) {
    if (maxMatches <= 0) return _matchCardHeight;
    return _matchCardHeight + (maxMatches - 1) * _unit;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final appBarFg = theme.appBarTheme.foregroundColor ?? cs.onBackground;

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
            icon: Icon(Icons.sync_rounded, color: cs.primary),
            tooltip: l10n.tr('knockout_bracket_reload_tooltip'),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: cs.primary))
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _matches.isEmpty ? _buildEmptyState() : _buildPremiumBracket(),
            ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Glass(
        padding: const EdgeInsets.all(32),
        borderRadius: 24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_outlined, size: 48, color: cs.onSurface.withOpacity(0.25)),
            const SizedBox(height: 16),
            Text(
              l10n.tr('knockout_bracket_empty_state'),
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface.withOpacity(0.72), fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumBracket() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final rounds = <String, List<KnockoutMatch>>{};
    for (final m in _matches) {
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

    final thirdPlace = (rounds['3rd Place'] ?? const <KnockoutMatch>[]);
    final thirdPlaceMatch = thirdPlace.isNotEmpty ? thirdPlace.first : null;

    // We build the premium bracket for the single-leg rounds only.
    // (Play-off is two-legged and should be displayed separately for clarity.)
    final playoffMatches = (rounds['Play-off'] ?? const <KnockoutMatch>[]);

    final bracketRounds = <String>[
      for (final rn in const ['Round of 16', 'Quarter Finals', 'Semi Finals', 'Final'])
        if (rounds.containsKey(rn)) rn,
    ];

    final finalList = rounds['Final'] ?? const <KnockoutMatch>[];
    final finalMatch = finalList.isNotEmpty ? finalList.first : null;

    final preFinalRounds = bracketRounds.where((rn) => rn != 'Final').toList();

    // If we don't have any bracket rounds, fall back to a simple list presentation.
    if (preFinalRounds.isEmpty && finalMatch == null) {
      return Center(
        child: Text(
          l10n.tr('knockout_bracket_empty_state'),
          style: TextStyle(color: cs.onSurface.withOpacity(0.7), fontWeight: FontWeight.w700),
        ),
      );
    }

    // Split left/right for each pre-final round.
    final leftByRound = <String, List<KnockoutMatch>>{};
    final rightByRound = <String, List<KnockoutMatch>>{};

    for (final rn in preFinalRounds) {
      final list = List<KnockoutMatch>.from(rounds[rn] ?? const <KnockoutMatch>[]);

      final leftCount = (list.length == 1) ? 1 : (list.length ~/ 2);
      final left = list.sublist(0, math.min(leftCount, list.length));
      final right = list.sublist(math.min(leftCount, list.length));

      leftByRound[rn] = left;
      rightByRound[rn] = right.reversed.toList(); // mirror feel
    }

    // Determine earliest round used for spacing.
    final firstRound = preFinalRounds.isNotEmpty ? preFinalRounds.first : null;
    final maxMatches = (firstRound == null) ? 1 : (leftByRound[firstRound]?.length ?? 1);

    // If it’s not power-of-two, don’t draw bracket lines (avoid broken visuals).
    final canDraw = _isPowerOfTwo(maxMatches);
    final totalHeight = _totalHeightForMaxMatches(maxMatches);

    return Column(
      children: [
        const SizedBox(height: 10),
        _buildHeaderInfo(),
        const SizedBox(height: 16),
        Expanded(
          child: InteractiveViewer(
            constrained: false,
            boundaryMargin: const EdgeInsets.all(180),
            minScale: 0.25,
            maxScale: 2.0,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (playoffMatches.isNotEmpty) ...[
                    _buildPlayoffSection(playoffMatches),
                    const SizedBox(height: 24),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // LEFT SIDE (normal LTR progression to center)
                      _buildSideBracket(
                        sideTitleRounds: preFinalRounds,
                        byRound: leftByRound,
                        maxMatches: maxMatches,
                        totalHeight: totalHeight,
                        isLeftToRight: true,
                        canDraw: canDraw,
                        textDirection: TextDirection.ltr,
                      ),

                      // CENTER FINAL (cup watermark + final match positioned in bracket space)
                      _buildCenterFinalColumn(
                        maxMatches: maxMatches,
                        totalHeight: totalHeight,
                        finalMatch: finalMatch,
                        canDraw: canDraw,
                      ),

                      // RIGHT SIDE (RTL layout so early rounds sit far right, progression to center)
                      _buildSideBracket(
                        sideTitleRounds: preFinalRounds,
                        byRound: rightByRound,
                        maxMatches: maxMatches,
                        totalHeight: totalHeight,
                        isLeftToRight: false,
                        canDraw: canDraw,
                        textDirection: TextDirection.rtl,
                      ),
                    ],
                  ),
                  if (thirdPlaceMatch != null) ...[
                    const SizedBox(height: 28),
                    _buildBottomExtraMatch(
                      title: _roundDisplayName('3rd Place'),
                      match: thirdPlaceMatch,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.tr('knockout_bracket_matches_scheduled_suffix'),
          style: TextStyle(
            color: cs.onSurface.withOpacity(0.35),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildPlayoffSection(List<KnockoutMatch> playoffMatches) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 520,
          child: Glass(
            borderRadius: 30,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Text(
              _roundDisplayName('Play-off').toUpperCase(),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final m in playoffMatches) SizedBox(width: _colWidth, child: _buildMatchCard(m)),
          ],
        ),
      ],
    );
  }

  Widget _buildSideBracket({
    required List<String> sideTitleRounds,
    required Map<String, List<KnockoutMatch>> byRound,
    required int maxMatches,
    required double totalHeight,
    required bool isLeftToRight,
    required bool canDraw,
    required TextDirection textDirection,
  }) {
    final children = <Widget>[];

    for (int i = 0; i < sideTitleRounds.length; i++) {
      final rn = sideTitleRounds[i];
      final matches = byRound[rn] ?? const <KnockoutMatch>[];
      if (matches.isEmpty) continue;

      children.add(
        _buildBracketRoundColumn(
          title: _roundDisplayName(rn),
          matches: matches,
          maxMatches: maxMatches,
          totalHeight: totalHeight,
        ),
      );

      // Connector to next round (or to center final)
      children.add(
        SizedBox(
          width: _connectorWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 58),
            child: SizedBox(
              height: totalHeight,
              child: canDraw
                  ? CustomPaint(
                      painter: BracketPainter(
                        maxMatches: maxMatches,
                        fromMatchCount: matches.length,
                        isLeftToRight: isLeftToRight,
                        cardHeight: _matchCardHeight,
                        baseGap: _baseGap,
                        lineColor: Theme.of(context).colorScheme.primary.withOpacity(0.35),
                        strokeWidth: 1.9,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: textDirection,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildCenterFinalColumn({
    required int maxMatches,
    required double totalHeight,
    required KnockoutMatch? finalMatch,
    required bool canDraw,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final top = canDraw
        ? (_centerY(maxMatches: maxMatches, count: 1, index: 0) - (_matchCardHeight / 2.0))
        : (totalHeight / 2.0 - _matchCardHeight / 2.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          SizedBox(
            width: _centerWidth,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Glass(
                borderRadius: 30,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: Text(
                  _roundDisplayName('Final').toUpperCase(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: _centerWidth,
            height: totalHeight,
            child: Stack(
              children: [
                // Cup watermark in the true center of the bracket.
                Align(
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.emoji_events_rounded,
                    size: 170,
                    color: cs.primary.withOpacity(0.10),
                  ),
                ),
                Positioned(
                  top: top,
                  left: 0,
                  right: 0,
                  child: SizedBox(
                    height: _matchCardHeight,
                    child: _buildFinalShowcase(finalMatch),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderInfo() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          Glass(
            borderRadius: 18,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.tr('knockout_bracket_header_title'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_matches.length} ${l10n.tr('knockout_bracket_matches_scheduled_suffix')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: cs.primary.withOpacity(0.08),
                    border: Border.all(color: cs.primary.withOpacity(0.16)),
                  ),
                  child: Icon(Icons.account_tree_rounded, color: cs.primary, size: 20),
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
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: const BorderRadiusDirectional.only(
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

  Widget _buildBracketRoundColumn({
    required String title,
    required List<KnockoutMatch> matches,
    required int maxMatches,
    required double totalHeight,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final roundIndex = _roundIndexForCount(maxMatches: maxMatches, count: matches.length);

    return Column(
      children: [
        SizedBox(
          width: _colWidth,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Glass(
              borderRadius: 30,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
              child: Text(
                title.toUpperCase(),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: _colWidth,
          height: totalHeight,
          child: Stack(
            children: [
              for (int i = 0; i < matches.length; i++)
                Positioned(
                  top: _centerY(maxMatches: maxMatches, count: matches.length, index: i) - (_matchCardHeight / 2.0),
                  left: 0,
                  right: 0,
                  child: SizedBox(
                    height: _matchCardHeight,
                    child: _buildMatchCard(matches[i]),
                  ),
                ),
            ],
          ),
        ),
        // RoundIndex used implicitly through centerY() math; keep var to validate logic in future.
        if (roundIndex < 0) const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildFinalShowcase(KnockoutMatch? m) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    final homeId = m?.homeTeamId;
    final awayId = m?.awayTeamId;

    final homeName = _teamName(homeId) ?? (homeId ?? l10n.tr('fixtures_tbd'));
    final awayName = _teamName(awayId) ?? (awayId ?? l10n.tr('fixtures_tbd'));

    final finished = m != null && _isFinished(m);

    bool isHomeWinner = false;
    bool isAwayWinner = false;

    if (m != null && finished) {
      if (m.homeScore! > m.awayScore!) {
        isHomeWinner = true;
      } else if (m.awayScore! > m.homeScore!) {
        isAwayWinner = true;
      } else if (m.tiebreakWinnerTeamId != null) {
        isHomeWinner = m.tiebreakWinnerTeamId == m.homeTeamId;
        isAwayWinner = m.tiebreakWinnerTeamId == m.awayTeamId;
      }
    }

    return Glass(
      borderRadius: 20,
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: _finalTeamTile(
                  name: homeName,
                  score: m?.homeScore,
                  emphasis: isHomeWinner,
                  alignEnd: false,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary.withOpacity(0.12),
                    border: Border.all(color: cs.primary.withOpacity(0.18)),
                  ),
                  child: Icon(
                    Icons.emoji_events_rounded,
                    color: cs.primary,
                    size: 22,
                  ),
                ),
              ),
              Expanded(
                child: _finalTeamTile(
                  name: awayName,
                  score: m?.awayScore,
                  emphasis: isAwayWinner,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          Divider(color: onSurface.withOpacity(0.10), height: 1),
          Row(
            children: [
              Expanded(
                child: Text(
                  finished ? l10n.tr('admin_knockout_status_completed') : l10n.tr('admin_knockout_status_pending'),
                  style: TextStyle(
                    color: finished ? cs.primary : onSurface.withOpacity(0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              if (m != null && finished && m.homeScore == m.awayScore && m.tiebreakWinnerTeamId != null)
                Text(
                  '${l10n.tr('knockout_bracket_penalties_prefix')}${_teamName(m.tiebreakWinnerTeamId) ?? m.tiebreakWinnerTeamId}',
                  style: TextStyle(
                    color: onSurface.withOpacity(0.65),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                )
              else
                Text(
                  l10n.tr('admin_knockout_round_final'),
                  style: TextStyle(
                    color: onSurface.withOpacity(0.45),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _finalTeamTile({
    required String name,
    required int? score,
    required bool emphasis,
    required bool alignEnd,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    final resolvedNameColor = emphasis ? cs.primary : onSurface;
    final resolvedScoreColor = emphasis ? cs.primary : onSurface.withOpacity(0.85);

    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          name.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: theme.textTheme.titleSmall?.copyWith(
            color: resolvedNameColor,
            fontWeight: emphasis ? FontWeight.w900 : FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: emphasis ? cs.primary.withOpacity(0.12) : onSurface.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: emphasis ? cs.primary.withOpacity(0.20) : onSurface.withOpacity(0.10),
            ),
          ),
          child: Text(
            score == null ? '—' : '$score',
            style: TextStyle(
              color: resolvedScoreColor,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomExtraMatch({
    required String title,
    required KnockoutMatch match,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SizedBox(
      width: _centerWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Glass(
            borderRadius: 30,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(height: _matchCardHeight, child: _buildMatchCard(match)),
        ],
      ),
    );
  }

  Widget _buildMatchCard(KnockoutMatch match) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    final homeName = _teamName(match.homeTeamId) ?? (match.homeTeamId ?? l10n.tr('fixtures_tbd'));
    final awayName = _teamName(match.awayTeamId) ?? (match.awayTeamId ?? l10n.tr('fixtures_tbd'));

    final isTBD = match.homeTeamId == null || match.awayTeamId == null;

    bool isHomeWinner = false;
    bool isAwayWinner = false;

    String? subtitle;
    String? footer;

    if (match.roundName == 'Play-off') {
      subtitle = match.isSecondLeg ? l10n.tr('admin_knockout_leg2') : l10n.tr('admin_knockout_leg1');

      final other = _findOtherLeg(match);
      if (other != null && _isFinished(match) && _isFinished(other)) {
        final winner = _aggregateWinner(match);
        if (winner != null) {
          isHomeWinner = (winner == match.homeTeamId);
          isAwayWinner = (winner == match.awayTeamId);
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

        final agg = '${l10n.tr('knockout_bracket_aggregate_prefix')}$hAgg - $aAgg';

        String? pens;
        if (hAgg == aAgg) {
          final second = match.isSecondLeg ? match : (other.isSecondLeg ? other : null);
          if (second?.tiebreakWinnerTeamId != null) {
            pens =
                '${l10n.tr('knockout_bracket_penalties_prefix')}${_teamName(second!.tiebreakWinnerTeamId) ?? second.tiebreakWinnerTeamId}';
          } else {
            pens = l10n.tr('knockout_bracket_aggregate_tied_penalties_required');
          }
        }

        footer = pens == null ? agg : '$agg • $pens';
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
          footer =
              '${l10n.tr('knockout_bracket_penalties_prefix')}${_teamName(match.tiebreakWinnerTeamId) ?? match.tiebreakWinnerTeamId}';
        } else {
          footer = l10n.tr('knockout_bracket_draw_winner_required');
        }
      }
    }

    final leftStripeColor = isTBD ? onSurface.withOpacity(0.22) : cs.primary;

    final footerIsWarn = footer == l10n.tr('knockout_bracket_draw_winner_required') ||
        footer == l10n.tr('knockout_bracket_aggregate_tied_penalties_required');

    return Stack(
      children: [
        Glass(
          borderRadius: 14,
          padding: const EdgeInsets.all(1),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: LinearGradient(
                colors: [
                  isTBD ? onSurface.withOpacity(0.06) : cs.primary.withOpacity(0.10),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subtitle ?? match.roundName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: onSurface.withOpacity(0.55),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      if (match.roundName != 'Play-off')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _isFinished(match) ? cs.primary.withOpacity(0.14) : onSurface.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: onSurface.withOpacity(0.10)),
                          ),
                          child: Text(
                            _isFinished(match)
                                ? context.l10n.tr('admin_knockout_status_completed')
                                : context.l10n.tr('admin_knockout_status_pending'),
                            style: TextStyle(
                              color: _isFinished(match) ? cs.primary : onSurface.withOpacity(0.55),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildTeamRow(homeName, match.homeScore?.toString() ?? "-", isHomeWinner),
                  const SizedBox(height: 8),
                  Divider(color: onSurface.withOpacity(0.10), height: 1),
                  const SizedBox(height: 8),
                  _buildTeamRow(awayName, match.awayScore?.toString() ?? "-", isAwayWinner),
                  const Spacer(),
                  if (footer != null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        footer!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: footerIsWarn ? const Color(0xFFF59E0B) : onSurface.withOpacity(0.60),
                          fontSize: 11,
                          fontWeight: footerIsWarn ? FontWeight.w900 : FontWeight.w700,
                        ),
                      ),
                    ),
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
              color: leftStripeColor,
              borderRadius: const BorderRadiusDirectional.only(
                topStart: Radius.circular(14),
                bottomStart: Radius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTeamRow(String name, String score, bool isWinner) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    final baseTextColor = (score == "-") ? onSurface.withOpacity(0.45) : onSurface;
    final nameColor = isWinner ? cs.primary : baseTextColor;

    return Row(
      children: [
        Expanded(
          child: Text(
            name.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: nameColor,
              fontSize: 13,
              fontWeight: isWinner ? FontWeight.w900 : FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isWinner ? cs.primary.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isWinner ? cs.primary.withOpacity(0.18) : Colors.transparent,
            ),
          ),
          child: Text(
            score,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isWinner ? cs.primary : onSurface,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
