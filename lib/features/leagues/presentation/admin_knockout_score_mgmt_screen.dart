import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../data/leagues_repository_local.dart';
import '../domain/logic/tournament_controller.dart';
import '../models/knockout_match.dart';
import '../models/enums.dart';

class AdminKnockoutScoreMgmtScreen extends ConsumerStatefulWidget {
  final String leagueId;

  const AdminKnockoutScoreMgmtScreen({
    super.key,
    required this.leagueId,
  });

  @override
  ConsumerState<AdminKnockoutScoreMgmtScreen> createState() => _AdminKnockoutScoreMgmtScreenState();
}

class _AdminKnockoutScoreMgmtScreenState extends ConsumerState<AdminKnockoutScoreMgmtScreen> {
  late LocalLeaguesRepository _repo;
  bool _isLoading = true;
  List<KnockoutMatch> _matches = [];
  Map<String, String> _teamNames = {};

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

  void _toast(String msg, {Color bg = const Color(0xFF101522), Color fg = Colors.white}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        backgroundColor: bg,
        content: Text(msg, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _toastOk(String msg) => _toast(msg, bg: Colors.cyanAccent.withOpacity(0.18), fg: Colors.cyanAccent);
  void _toastWarn(String msg) => _toast(msg, bg: Colors.orangeAccent.withOpacity(0.14), fg: Colors.orangeAccent);
  void _toastErr(String msg) => _toast(msg, bg: Colors.redAccent.withOpacity(0.14), fg: Colors.redAccent);

  String _pairKey(String a, String b) => (a.compareTo(b) < 0) ? '$a|$b' : '$b|$a';

  bool _isFinished(KnockoutMatch m) {
    final done = (m.status == MatchStatus.played || m.status == MatchStatus.completed);
    return done && m.homeScore != null && m.awayScore != null;
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

  KnockoutMatch? _findOtherPlayoffLeg({
    required KnockoutMatch leg,
    required List<KnockoutMatch> all,
  }) {
    if (leg.roundName != 'Play-off') return null;
    final a = leg.homeTeamId;
    final b = leg.awayTeamId;
    final nextId = leg.nextMatchId;
    if (a == null || b == null || nextId == null) return null;

    final key = _pairKey(a, b);

    for (final m in all) {
      if (m.id == leg.id) continue;
      if (m.roundName != 'Play-off') continue;
      if (m.nextMatchId != nextId) continue;
      final ha = m.homeTeamId;
      final aa = m.awayTeamId;
      if (ha == null || aa == null) continue;
      if (_pairKey(ha, aa) != key) continue;
      return m;
    }
    return null;
  }

  Future<String?> _promptPenaltyWinner({
    required String homeId,
    required String awayId,
    required String contextLabel,
  }) async {
    final l10n = context.l10n;

    final homeName = _teamNames[homeId] ?? homeId;
    final awayName = _teamNames[awayId] ?? awayId;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF000428),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Colors.white24),
          ),
          title: Text(
            l10n.tr('admin_knockout_penalties_title'),
            style: const TextStyle(color: Colors.white),
          ),
          content: Text(
            '$contextLabel\n${l10n.tr('admin_knockout_select_winner_to_advance')}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, homeId),
              child: Text(homeName.toUpperCase()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, awayId),
              child: Text(awayName.toUpperCase()),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final teams = await _repo.getTeams(widget.leagueId);
    final matches = await _repo.getKnockoutMatches(widget.leagueId);

    // Stable order: round order; for Play-off order by nextMatchId then leg.
    matches.sort((a, b) {
      final ai = _roundOrder.indexOf(a.roundName);
      final bi = _roundOrder.indexOf(b.roundName);
      if (ai != bi) {
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      }

      if (a.roundName == 'Play-off' && b.roundName == 'Play-off') {
        final an = (a.nextMatchId ?? '');
        final bn = (b.nextMatchId ?? '');
        final c1 = an.compareTo(bn);
        if (c1 != 0) return c1;

        // Leg 1 first
        final c2 = (a.isSecondLeg ? 1 : 0).compareTo(b.isSecondLeg ? 1 : 0);
        if (c2 != 0) return c2;
      }

      return a.id.compareTo(b.id);
    });

    if (!mounted) return;
    setState(() {
      _matches = matches;
      _teamNames = {for (final t in teams) t.id: t.name};
      _isLoading = false;
    });
  }

  Future<void> _updateScore(
    KnockoutMatch match,
    int hScore,
    int aScore,
  ) async {
    final l10n = context.l10n;

    var updatedMatch = match.copyWith(
      homeScore: hScore,
      awayScore: aScore,
      status: MatchStatus.completed,
    );

    // Apply to local list.
    final all = [..._matches];
    final idx = all.indexWhere((m) => m.id == match.id);
    if (idx != -1) {
      all[idx] = updatedMatch;
    } else {
      all.add(updatedMatch);
    }

    // ------------------------------------------------------------------
    // CRITICAL FIX: single-match knockout rounds must not end as a draw
    // unless a tiebreakWinnerTeamId is provided.
    // Applies to: R16/QF/SF/Final/3rd Place (NOT Play-off, which can draw in leg 1).
    // ------------------------------------------------------------------
    if (updatedMatch.roundName != 'Play-off') {
      final hId = updatedMatch.homeTeamId;
      final aId = updatedMatch.awayTeamId;

      if (hId == null || aId == null) {
        if (hScore == aScore) {
          _toastErr(l10n.tr('admin_knockout_cannot_save_draw_tbd'));
          return;
        }
      } else {
        if (hScore == aScore) {
          final winner = await _promptPenaltyWinner(
            homeId: hId,
            awayId: aId,
            contextLabel: l10n.tr('admin_knockout_draw_requires_winner'),
          );
          if (winner == null) {
            _toastErr(l10n.tr('admin_knockout_winner_required'));
            return;
          }
          updatedMatch = updatedMatch.copyWith(tiebreakWinnerTeamId: winner);
        } else {
          // Clear any previously set penalty winner when score is decisive.
          if (updatedMatch.tiebreakWinnerTeamId != null) {
            updatedMatch = updatedMatch.copyWith(tiebreakWinnerTeamId: null);
          }
        }

        // Update in local list
        final idx2 = all.indexWhere((m) => m.id == updatedMatch.id);
        if (idx2 != -1) all[idx2] = updatedMatch;
      }
    }

    // ------------------------------------------------------------------
    // Play-off (two-legged) aggregate handling:
    // - Only applies to SECOND leg when BOTH legs are finished.
    // - If aggregate tied after leg 2 -> require penalties winner on leg 2.
    // ------------------------------------------------------------------
    if (updatedMatch.roundName == 'Play-off' && updatedMatch.isSecondLeg) {
      final other = _findOtherPlayoffLeg(leg: updatedMatch, all: all);
      if (other != null && _isFinished(updatedMatch) && _isFinished(other)) {
        final aId = updatedMatch.homeTeamId;
        final bId = updatedMatch.awayTeamId;

        if (aId != null && bId != null) {
          final totals = <String, int>{aId: 0, bId: 0};

          void add(KnockoutMatch m) {
            totals[m.homeTeamId!] = (totals[m.homeTeamId!] ?? 0) + m.homeScore!;
            totals[m.awayTeamId!] = (totals[m.awayTeamId!] ?? 0) + m.awayScore!;
          }

          add(updatedMatch);
          add(other);

          final aTot = totals[aId] ?? 0;
          final bTot = totals[bId] ?? 0;

          if (aTot == bTot) {
            final winner = await _promptPenaltyWinner(
              homeId: aId,
              awayId: bId,
              contextLabel: l10n.tr('admin_knockout_aggregate_tied_after_leg2'),
            );
            if (winner == null) {
              _toastErr(l10n.tr('admin_knockout_aggregate_winner_required'));
              return;
            }

            updatedMatch = updatedMatch.copyWith(tiebreakWinnerTeamId: winner);

            final idx2 = all.indexWhere((m) => m.id == updatedMatch.id);
            if (idx2 != -1) all[idx2] = updatedMatch;
          } else {
            // Not tied -> clear any previously set tiebreak winner.
            if (updatedMatch.tiebreakWinnerTeamId != null) {
              updatedMatch = updatedMatch.copyWith(tiebreakWinnerTeamId: null);
              final idx2 = all.indexWhere((m) => m.id == updatedMatch.id);
              if (idx2 != -1) all[idx2] = updatedMatch;
            }
          }
        }
      }
    }

    // Auto-advance winners.
    final advanced = TournamentController.processMatchResult(
      completedMatch: updatedMatch,
      allMatches: all,
    );

    await _repo.saveKnockoutMatches(widget.leagueId, advanced);

    if (!mounted) return;
    setState(() => _matches = advanced);

    _toastOk(l10n.tr('admin_knockout_score_updated_toast'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = MediaQuery.of(context).size.width;
    final isTablet = width > 700;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('admin_knockout_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadData,
            tooltip: l10n.tr('admin_knockout_reload_tooltip'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.cyanAccent),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isTablet ? 1000 : 600,
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SectionHeader(l10n.tr('admin_knockout_section_title')),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          l10n.tr('admin_knockout_section_description'),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _matches.isEmpty
                            ? Center(
                                child: Text(
                                  l10n.tr('admin_knockout_empty_state'),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 13,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : _buildGroupedList(),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildGroupedList() {
    final byRound = <String, List<KnockoutMatch>>{};
    for (final m in _matches) {
      byRound.putIfAbsent(m.roundName, () => []).add(m);
    }

    final rounds = byRound.keys.toList()
      ..sort((a, b) {
        final ai = _roundOrder.indexOf(a);
        final bi = _roundOrder.indexOf(b);
        if (ai == -1 && bi == -1) return a.compareTo(b);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rounds.length,
      itemBuilder: (context, idx) {
        final roundName = rounds[idx];
        final ms = byRound[roundName]!;
        return Padding(
          padding: EdgeInsets.only(bottom: idx == rounds.length - 1 ? 0 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _roundDisplayName(roundName),
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              for (final m in ms)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ScoreEntryTile(
                    match: m,
                    homeName: _teamNames[m.homeTeamId ?? ''] ?? (m.homeTeamId ?? 'TBD'),
                    awayName: _teamNames[m.awayTeamId ?? ''] ?? (m.awayTeamId ?? 'TBD'),
                    onSave: (h, a) => _updateScore(m, h, a),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ScoreEntryTile extends StatefulWidget {
  final KnockoutMatch match;
  final String homeName;
  final String awayName;
  final Function(int, int) onSave;

  const _ScoreEntryTile({
    super.key,
    required this.match,
    required this.homeName,
    required this.awayName,
    required this.onSave,
  });

  @override
  State<_ScoreEntryTile> createState() => _ScoreEntryTileState();
}

class _ScoreEntryTileState extends State<_ScoreEntryTile> {
  late int _homeScore;
  late int _awayScore;

  @override
  void initState() {
    super.initState();
    _homeScore = widget.match.homeScore ?? 0;
    _awayScore = widget.match.awayScore ?? 0;
  }

  bool get _isCompleted => widget.match.status == MatchStatus.completed || widget.match.status == MatchStatus.played;

  void _incHome() => setState(() => _homeScore++);
  void _decHome() => setState(() {
        if (_homeScore > 0) _homeScore--;
      });

  void _incAway() => setState(() => _awayScore++);
  void _decAway() => setState(() {
        if (_awayScore > 0) _awayScore--;
      });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final isPlayoff = widget.match.roundName == 'Play-off';
    final legLabel = isPlayoff
        ? (widget.match.isSecondLeg ? l10n.tr('admin_knockout_leg2') : l10n.tr('admin_knockout_leg1'))
        : null;

    return Glass(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (legLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                legLabel,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.homeName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  l10n.tr('league_details_vs'),
                  style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  widget.awayName,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _isCompleted ? Colors.cyanAccent.withOpacity(0.12) : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _isCompleted ? l10n.tr('admin_knockout_status_completed') : l10n.tr('admin_knockout_status_pending'),
                  style: TextStyle(
                    color: _isCompleted ? Colors.cyanAccent : Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _scoreStepper(value: _homeScore, onInc: _incHome, onDec: _decHome),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(":", style: TextStyle(color: Colors.white38, fontSize: 24)),
              ),
              _scoreStepper(value: _awayScore, onInc: _incAway, onDec: _decAway),
              const SizedBox(width: 24),
              IconButton.filled(
                onPressed: () {
                  widget.onSave(_homeScore, _awayScore);
                  FocusScope.of(context).unfocus();
                },
                style: IconButton.styleFrom(
                  backgroundColor: Colors.cyanAccent.withOpacity(0.2),
                  foregroundColor: Colors.cyanAccent,
                ),
                icon: const Icon(Icons.done_all, size: 24),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scoreStepper({
    required int value,
    required VoidCallback onInc,
    required VoidCallback onDec,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepperButton(icon: Icons.remove, onPressed: value > 0 ? onDec : null, enabled: value > 0),
          const SizedBox(width: 6),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 6),
          _stepperButton(icon: Icons.add, onPressed: onInc, enabled: true),
        ],
      ),
    );
  }

  Widget _stepperButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required bool enabled,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: enabled ? Colors.cyanAccent.withOpacity(0.08) : Colors.white.withOpacity(0.02),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: enabled ? Colors.cyanAccent : Colors.white24),
      ),
    );
  }
}
