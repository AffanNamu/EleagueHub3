// lib/features/leagues/presentation/knockout_bracket_screen.dart
//
// REDESIGNED KNOCKOUT UI
// ----------------------------------------------------------------------------
// This screen now ships with two view modes, toggled from the app bar:
//
//  1) "Rounds" view (default) — inspired by modern score-center apps:
//     a horizontal round selector (Round of 32 / Round of 16 / Quarter-final /
//     Semi-final / Final) sits under the app bar. Each round renders as a
//     clean vertical list of match cards (team crest, name, score, winner
//     highlighted). Where two matches feed into an already-known next match,
//     a bracket connector links them visually to a compact preview of that
//     next match — exactly like the reference design. The Final tab shows a
//     dedicated hero card (gradient background, big trophy, big score, venue
//     line) plus the Bronze/3rd-place match underneath.
//
//  2) "Bracket" (tree) view — the original full-tournament tree with
//     zoomable/pannable columns and connector lines, kept for anyone who
//     wants the whole bracket at a glance. Its match-card styling was
//     unified with the new "Rounds" view so both look consistent.
//
// All original data loading, two-legged play-off aggregate logic, FIFA
// World Cup round support ('Round of 32'), and team-image resolution are
// preserved unchanged. The only functional addition is the shared
// `_computeMatchDisplayInfo` helper, which both view modes use so winner /
// footer / status logic can never drift between the two presentations.
// ----------------------------------------------------------------------------

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../widgets/bracket_painter.dart';
import '../data/leagues_repository_local.dart';
import '../models/enums.dart';
import '../models/knockout_match.dart';
import '../models/team.dart';

/// Small, immutable bundle of everything the UI needs to render a single
/// knockout match consistently, regardless of which view (tree or list)
/// is drawing it. Centralising this avoids the winner/footer logic ever
/// diverging between the two presentations.
class _MatchDisplayInfo {
  const _MatchDisplayInfo({
    required this.subtitleOverrideOrRoundName,
    this.footer,
    this.footerIsWarn = false,
    this.isHomeWinner = false,
    this.isAwayWinner = false,
    required this.isTBD,
    required this.isFinished,
  });

  final String subtitleOverrideOrRoundName;
  final String? footer;
  final bool footerIsWarn;
  final bool isHomeWinner;
  final bool isAwayWinner;
  final bool isTBD;
  final bool isFinished;
}

class KnockoutBracketScreen extends ConsumerStatefulWidget {
  final String leagueId;

  const KnockoutBracketScreen({
    super.key,
    required this.leagueId,
  });

  @override
  ConsumerState<KnockoutBracketScreen> createState() =>
      _KnockoutBracketScreenState();
}

class _KnockoutBracketScreenState
    extends ConsumerState<KnockoutBracketScreen> {
  late LocalLeaguesRepository _repo;

  bool _isLoading = true;
  String? _loadError;

  List<KnockoutMatch> _matches = [];
  Map<String, Team> _teamsById = {};

  Map<String, String> _teamImageUrls = {};
  final Set<String> _requestedUserImageIds = <String>{};
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── View-mode state ────────────────────────────────────────────────────
  // false => new "Rounds" list view (default, matches the reference video).
  // true  => original full bracket tree view.
  bool _showTree = false;
  String? _selectedRound;

  static const double _colWidth = 240;
  static const double _centerWidth = 320;
  static const double _connectorWidth = 56;

  static const double _matchCardHeight = 132;
  static const double _baseGap = 22;
  static const double _unit = _matchCardHeight + _baseGap;

  // MODIFIED: Added 'Round of 32' before 'Round of 16' for World Cup 48-team.
  static const _roundOrder = <String>[
    'Play-off',
    'Round of 32', // World Cup FIFA 2026 (48-team)
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

  bool _looksLikeFirebaseUid(String s) => s.trim().length > 20;

  String _bestUserImageUrlFromUserDoc(Map<String, dynamic> data) {
    final teamImageUrl = (data['teamImageUrl'] as String?)?.trim() ?? '';
    if (teamImageUrl.isNotEmpty) return teamImageUrl;

    final profileImageUrl =
        (data['profileImageUrl'] as String?)?.trim() ?? '';
    if (profileImageUrl.isNotEmpty) return profileImageUrl;

    final photoUrl = (data['photoUrl'] as String?)?.trim() ?? '';
    if (photoUrl.isNotEmpty) return photoUrl;

    return '';
  }

  Future<Map<String, String>> _fetchUserImagesByIds(
      List<String> ids) async {
    final clean = ids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && _looksLikeFirebaseUid(e))
        .toList(growable: false);
    if (clean.isEmpty) return const <String, String>{};

    final out = <String, String>{};

    const chunkSize = 10;
    for (var i = 0; i < clean.length; i += chunkSize) {
      final chunk = clean.sublist(
        i,
        (i + chunkSize > clean.length) ? clean.length : i + chunkSize,
      );

      final snap = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      for (final d in snap.docs) {
        final url = _bestUserImageUrlFromUserDoc(d.data());
        if (url.trim().isNotEmpty) out[d.id] = url.trim();
      }
    }

    return out;
  }

  Future<void> _ensureUserImagesForTeamIds(
      Iterable<String?> ids) async {
    final missing = <String>[];
    for (final id in ids) {
      final clean = (id ?? '').trim();
      if (clean.isEmpty) continue;
      if (!_looksLikeFirebaseUid(clean)) continue;
      if (_requestedUserImageIds.contains(clean)) continue;
      _requestedUserImageIds.add(clean);

      if ((_teamImageUrls[clean] ?? '').trim().isNotEmpty) continue;
      missing.add(clean);
    }

    if (missing.isEmpty) return;

    try {
      final userImages = await _fetchUserImagesByIds(missing);
      if (!mounted) return;
      if (userImages.isEmpty) return;

      setState(() {
        _teamImageUrls = {..._teamImageUrls, ...userImages};
      });
    } catch (_) {}
  }

  String _teamImageUrlForId(String? id) {
    final clean = (id ?? '').trim();
    if (clean.isEmpty) return '';

    final fromTeam = _teamsById[clean]?.teamImageUrl.trim() ?? '';
    if (fromTeam.isNotEmpty) return fromTeam;

    final fromMap = (_teamImageUrls[clean] ?? '').trim();
    if (fromMap.isNotEmpty) return fromMap;

    return '';
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      if (uid.isEmpty) {
        if (mounted) context.go('/login');
        return;
      }

      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));

      final teams = await _repo
          .getTeams(widget.leagueId)
          .timeout(const Duration(seconds: 20));
      final koMatches = await _repo
          .getKnockoutMatches(widget.leagueId)
          .timeout(const Duration(seconds: 25));

      final localImages = <String, String>{};
      for (final t in teams) {
        final id = t.id.trim();
        final url = t.teamImageUrl.trim();
        if (id.isNotEmpty && url.isNotEmpty) localImages[id] = url;
      }

      if (!mounted) return;

      final defaultRound = _computeDefaultRound(koMatches);

      setState(() {
        _teamsById = {for (final t in teams) t.id: t};
        _teamImageUrls = localImages;
        _matches = koMatches;
        _isLoading = false;
        _selectedRound ??= defaultRound;
      });

      final idsFromMatches = <String?>{
        for (final m in koMatches) m.homeTeamId,
        for (final m in koMatches) m.awayTeamId,
      };
      unawaited(_ensureUserImagesForTeamIds(idsFromMatches));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = UserFriendlyError.toMessage(
            e is Object ? e : Exception('unknown'));
      });
    }
  }

  // MODIFIED: Added 'Round of 32' display name for World Cup 48-team bracket.
  String _roundDisplayName(String roundName) {
    final l10n = context.l10n;
    switch (roundName) {
      case 'Play-off':
        return l10n.tr('admin_knockout_round_playoff');
      case 'Round of 32':
        // World Cup 48-team format.
        return 'Round of 32';
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

  String _pairKey(String a, String b) =>
      (a.compareTo(b) < 0) ? '$a|$b' : '$b|$a';

  bool _isFinished(KnockoutMatch m) {
    final done = (m.status == MatchStatus.played ||
        m.status == MatchStatus.completed);
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

    final second = leg.isSecondLeg
        ? leg
        : (other.isSecondLeg ? other : null);
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
    final r =
        _roundIndexForCount(maxMatches: maxMatches, count: count);
    final pow2 = 1 << r;

    final offset = ((pow2 - 1) / 2.0) * _unit;
    final step = pow2 * _unit;

    return (_matchCardHeight / 2.0) + offset + index * step;
  }

  double _totalHeightForMaxMatches(int maxMatches) {
    if (maxMatches <= 0) return _matchCardHeight;
    return _matchCardHeight + (maxMatches - 1) * _unit;
  }

  // ── Shared match-display logic (used by both tree + list views) ────────

  _MatchDisplayInfo _computeMatchDisplayInfo(KnockoutMatch match) {
    final l10n = context.l10n;
    final isTBD = match.homeTeamId == null || match.awayTeamId == null;

    bool isHomeWinner = false;
    bool isAwayWinner = false;

    String? subtitle;
    String? footer;
    bool footerIsWarn = false;

    final finished = _isFinished(match);

    if (match.roundName == 'Play-off') {
      subtitle = match.isSecondLeg
          ? l10n.tr('admin_knockout_leg2')
          : l10n.tr('admin_knockout_leg1');

      final other = _findOtherLeg(match);
      if (other != null && finished && _isFinished(other)) {
        final winner = _aggregateWinner(match);
        if (winner != null) {
          isHomeWinner = (winner == match.homeTeamId);
          isAwayWinner = (winner == match.awayTeamId);
        }

        final hId = match.homeTeamId!;
        final aId = match.awayTeamId!;
        final totals = <String, int>{};

        void add(KnockoutMatch m) {
          totals[m.homeTeamId!] =
              (totals[m.homeTeamId!] ?? 0) + m.homeScore!;
          totals[m.awayTeamId!] =
              (totals[m.awayTeamId!] ?? 0) + m.awayScore!;
        }

        add(match);
        add(other);

        final hAgg = totals[hId] ?? 0;
        final aAgg = totals[aId] ?? 0;

        final agg =
            '${l10n.tr('knockout_bracket_aggregate_prefix')}$hAgg - $aAgg';

        String? pens;
        if (hAgg == aAgg) {
          final second = match.isSecondLeg
              ? match
              : (other.isSecondLeg ? other : null);
          if (second?.tiebreakWinnerTeamId != null) {
            pens =
                '${l10n.tr('knockout_bracket_penalties_prefix')}${_teamName(second!.tiebreakWinnerTeamId) ?? second.tiebreakWinnerTeamId}';
          } else {
            pens = l10n.tr(
                'knockout_bracket_aggregate_tied_penalties_required');
            footerIsWarn = true;
          }
        }

        footer = pens == null ? agg : '$agg • $pens';
      }
    } else {
      if (finished) {
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
          footerIsWarn = true;
        }
      }
    }

    return _MatchDisplayInfo(
      subtitleOverrideOrRoundName: subtitle ?? match.roundName,
      footer: footer,
      footerIsWarn: footerIsWarn,
      isHomeWinner: isHomeWinner,
      isAwayWinner: isAwayWinner,
      isTBD: isTBD,
      isFinished: finished,
    );
  }

  Color _statusAccentColor(ColorScheme cs, _MatchDisplayInfo info) {
    if (info.isTBD) return cs.onSurface.withOpacity(0.22);
    if (info.footerIsWarn) return const Color(0xFFF59E0B);
    if (info.isFinished) return const Color(0xFF22C55E);
    return cs.primary;
  }

  // ── Round bookkeeping shared by list + tab logic ────────────────────────

  Map<String, List<KnockoutMatch>> _groupByRound() {
    final rounds = <String, List<KnockoutMatch>>{};
    for (final m in _matches) {
      rounds.putIfAbsent(m.roundName, () => []).add(m);
    }
    return rounds;
  }

  /// Rounds in canonical order, for the tab bar. 'Final' and '3rd Place'
  /// are merged into a single "Final" tab (the Final tab shows both the
  /// title match and the bronze match beneath it).
  List<String> _tabRoundOrder(Set<String> present) {
    final tabs = <String>[];
    for (final r in _roundOrder) {
      if (r == '3rd Place') continue;
      if (r == 'Final') {
        if (present.contains('Final') || present.contains('3rd Place')) {
          tabs.add('Final');
        }
        continue;
      }
      if (present.contains(r)) tabs.add(r);
    }
    return tabs;
  }

  String? _computeDefaultRound(List<KnockoutMatch> matches) {
    if (matches.isEmpty) return null;

    final byRound = <String, List<KnockoutMatch>>{};
    for (final m in matches) {
      byRound.putIfAbsent(m.roundName, () => []).add(m);
    }

    final tabs = _tabRoundOrder(byRound.keys.toSet());

    for (final r in tabs) {
      final relevant = r == 'Final'
          ? <KnockoutMatch>[
              ...(byRound['Final'] ?? const <KnockoutMatch>[]),
              ...(byRound['3rd Place'] ?? const <KnockoutMatch>[]),
            ]
          : (byRound[r] ?? const <KnockoutMatch>[]);
      if (relevant.any((m) => !_isFinished(m))) return r;
    }

    return tabs.isNotEmpty ? tabs.last : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final appBarFg =
        theme.appBarTheme.foregroundColor ?? cs.onSurface;

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
            tooltip: _showTree
                ? 'Round-by-round view'
                : 'Full bracket view',
            onPressed: _isLoading
                ? null
                : () => setState(() => _showTree = !_showTree),
            icon: Icon(
              _showTree
                  ? Icons.view_agenda_rounded
                  : Icons.account_tree_rounded,
              color: cs.primary,
            ),
          ),
          IconButton(
            onPressed: _isLoading ? null : _loadData,
            icon: Icon(Icons.refresh, color: cs.primary),
            tooltip: l10n.tr('common_refresh'),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: cs.primary))
          : (_loadError != null
              ? _buildLoadErrorState(_loadError!)
              : Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  child: _matches.isEmpty
                      ? _buildEmptyState()
                      : (_showTree
                          ? _buildPremiumBracket()
                          : _buildListModeBody()),
                )),
    );
  }

  Widget _buildLoadErrorState(String msg) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Glass(
            borderRadius: 24,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_rounded,
                      color: cs.primary, size: 44),
                  const SizedBox(height: 10),
                  // FIX: Was curly apostrophe 'Couldn\u2019t'.
                  // Replaced with straight apostrophe 'Couldn\'t'.
                  Text(
                    "Couldn't load bracket",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    msg,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withOpacity(0.70),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.pop(),
                          child: const Text('Back'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _loadData,
                          child: const Text('Retry'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
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
            Icon(Icons.emoji_events_outlined,
                size: 48,
                color: cs.onSurface.withOpacity(0.25)),
            const SizedBox(height: 16),
            Text(
              l10n.tr('knockout_bracket_empty_state'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface.withOpacity(0.72),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyRoundState() {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_soccer_rounded,
                size: 40, color: cs.onSurface.withOpacity(0.25)),
            const SizedBox(height: 12),
            Text(
              'No matches yet for this round.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface.withOpacity(0.6),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // "ROUNDS" VIEW — round-tab selector + list of match cards (default UI)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildListModeBody() {
    final rounds = _groupByRound();
    final tabs = _tabRoundOrder(rounds.keys.toSet());

    if (tabs.isEmpty) return _buildEmptyState();

    final selected =
        (_selectedRound != null && tabs.contains(_selectedRound))
            ? _selectedRound!
            : tabs.last;

    return Column(
      children: [
        const SizedBox(height: 12),
        _buildRoundTabs(tabs, selected),
        const SizedBox(height: 18),
        Expanded(
          child: selected == 'Final'
              ? _buildFinalHeroSection(rounds)
              : _buildRoundListBody(selected, rounds),
        ),
      ],
    );
  }

  Widget _buildRoundTabs(List<String> tabs, String selected) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final r = tabs[i];
          final isSelected = r == selected;
          final label = r == 'Final' ? 'Final' : _roundDisplayName(r);

          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => setState(() => _selectedRound = r),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? cs.primary
                    : cs.onSurface.withOpacity(0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isSelected
                      ? cs.primary
                      : cs.onSurface.withOpacity(0.14),
                ),
              ),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? cs.onPrimary
                        : cs.onSurface.withOpacity(0.7),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRoundSummaryHeader(String round, int count) {
    final cs = Theme.of(context).colorScheme;
    final title = round == 'Final' ? 'Final' : _roundDisplayName(round);

    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: cs.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 8),
        if (count > 0)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRoundListBody(
    String roundName,
    Map<String, List<KnockoutMatch>> rounds,
  ) {
    final matches = List<KnockoutMatch>.from(
        rounds[roundName] ?? const <KnockoutMatch>[]);

    if (matches.isEmpty) return _buildEmptyRoundState();

    matches.sort((a, b) {
      final an = a.nextMatchId ?? '';
      final bn = b.nextMatchId ?? '';
      final c1 = an.compareTo(bn);
      if (c1 != 0) return c1;

      final c2 = (a.isSecondLeg ? 1 : 0)
          .compareTo(b.isSecondLeg ? 1 : 0);
      if (c2 != 0) return c2;

      return a.id.compareTo(b.id);
    });

    final children = <Widget>[
      _buildRoundSummaryHeader(roundName, matches.length),
      const SizedBox(height: 16),
    ];

    if (roundName == 'Play-off') {
      // Two-legged ties: no bracket-pair connector, just leg badges +
      // aggregate footer (handled by _computeMatchDisplayInfo already).
      for (final m in matches) {
        children.add(_buildListMatchCard(m));
      }
    } else {
      final matchesById = {for (final m in _matches) m.id: m};

      final byNext = <String, List<KnockoutMatch>>{};
      final singles = <KnockoutMatch>[];

      for (final m in matches) {
        final nm = (m.nextMatchId ?? '').trim();
        if (nm.isEmpty) {
          singles.add(m);
          continue;
        }
        byNext.putIfAbsent(nm, () => []).add(m);
      }

      for (final entry in byNext.entries) {
        final pair = entry.value;
        final nextMatch = matchesById[entry.key];
        children.add(_buildPairWithConnector(pair, nextMatch));
        children.add(const SizedBox(height: 20));
      }

      for (final m in singles) {
        children.add(_buildListMatchCard(m));
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }

  /// Renders two feeder matches stacked on the left, a bracket connector,
  /// and a compact preview of the match they feed into on the right —
  /// mirroring the reference design's round-by-round bracket list.
  Widget _buildPairWithConnector(
    List<KnockoutMatch> pair,
    KnockoutMatch? nextMatch,
  ) {
    final cs = Theme.of(context).colorScheme;
    final top = pair.isNotEmpty ? pair[0] : null;
    final bottom = pair.length > 1 ? pair[1] : null;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (top != null) _buildListMatchCard(top),
                if (bottom != null) _buildListMatchCard(bottom),
              ],
            ),
          ),
          SizedBox(
            width: 30,
            child: CustomPaint(
              painter: _BracketConnectorPainter(
                color: cs.primary.withOpacity(0.45),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          Expanded(
            flex: 4,
            child: Center(child: _buildNextPreviewCard(nextMatch)),
          ),
        ],
      ),
    );
  }

  Widget _buildNextPreviewCard(KnockoutMatch? nextMatch) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;

    if (nextMatch == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: onSurface.withOpacity(0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: onSurface.withOpacity(0.08)),
        ),
        child: Text(
          'TBD',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: onSurface.withOpacity(0.4),
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      );
    }

    final info = _computeMatchDisplayInfo(nextMatch);
    final homeName = _teamName(nextMatch.homeTeamId) ??
        (nextMatch.homeTeamId ?? l10n.tr('fixtures_tbd'));
    final awayName = _teamName(nextMatch.awayTeamId) ??
        (nextMatch.awayTeamId ?? l10n.tr('fixtures_tbd'));
    final homeUrl = _teamImageUrlForId(nextMatch.homeTeamId);
    final awayUrl = _teamImageUrlForId(nextMatch.awayTeamId);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: onSurface.withOpacity(0.035),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: onSurface.withOpacity(0.10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _roundDisplayName(nextMatch.roundName).toUpperCase(),
            style: TextStyle(
              color: onSurface.withOpacity(0.4),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 8),
          _miniTeamRow(
              homeUrl, homeName, nextMatch.homeScore, info.isHomeWinner),
          const SizedBox(height: 8),
          _miniTeamRow(
              awayUrl, awayName, nextMatch.awayScore, info.isAwayWinner),
        ],
      ),
    );
  }

  Widget _miniTeamRow(String url, String name, int? score, bool isWinner) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;

    return Row(
      children: [
        _TeamThumb(url: url, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isWinner ? onSurface : onSurface.withOpacity(0.45),
              fontWeight: isWinner ? FontWeight.w900 : FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          score == null ? '-' : '$score',
          style: TextStyle(
            color: isWinner ? cs.primary : onSurface.withOpacity(0.5),
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// The main, full-size match card used throughout the "Rounds" list view.
  Widget _buildListMatchCard(KnockoutMatch match) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;

    final info = _computeMatchDisplayInfo(match);
    final accent = _statusAccentColor(cs, info);

    final homeName = _teamName(match.homeTeamId) ??
        (match.homeTeamId ?? l10n.tr('fixtures_tbd'));
    final awayName = _teamName(match.awayTeamId) ??
        (match.awayTeamId ?? l10n.tr('fixtures_tbd'));
    final homeUrl = _teamImageUrlForId(match.homeTeamId);
    final awayUrl = _teamImageUrlForId(match.awayTeamId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Stack(
        children: [
          Glass(
            borderRadius: 18,
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        info.subtitleOverrideOrRoundName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onSurface.withOpacity(0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: info.isTBD
                            ? onSurface.withOpacity(0.08)
                            : (info.isFinished
                                ? const Color(0xFF22C55E)
                                    .withOpacity(0.14)
                                : cs.primary.withOpacity(0.10)),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        info.isTBD
                            ? 'TBD'
                            : (info.isFinished
                                ? l10n.tr(
                                    'admin_knockout_status_completed')
                                : l10n.tr(
                                    'admin_knockout_status_pending')),
                        style: TextStyle(
                          color: info.isTBD
                              ? onSurface.withOpacity(0.5)
                              : (info.isFinished
                                  ? const Color(0xFF22C55E)
                                  : cs.primary),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _listTeamRow(
                    homeUrl, homeName, match.homeScore, info.isHomeWinner),
                const SizedBox(height: 10),
                _listTeamRow(
                    awayUrl, awayName, match.awayScore, info.isAwayWinner),
                if (info.footer != null) ...[
                  const SizedBox(height: 10),
                  Divider(color: onSurface.withOpacity(0.08), height: 1),
                  const SizedBox(height: 8),
                  Text(
                    info.footer!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: info.footerIsWarn
                          ? const Color(0xFFF59E0B)
                          : onSurface.withOpacity(0.6),
                      fontSize: 11.5,
                      fontWeight: info.footerIsWarn
                          ? FontWeight.w900
                          : FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          PositionedDirectional(
            top: 0,
            bottom: 0,
            start: 0,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: accent,
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

  Widget _listTeamRow(String url, String name, int? score, bool isWinner) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;

    return Row(
      children: [
        _TeamThumb(url: url, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isWinner ? onSurface : onSurface.withOpacity(0.42),
              fontWeight: isWinner ? FontWeight.w900 : FontWeight.w600,
              fontSize: 14.5,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          constraints: const BoxConstraints(minWidth: 36),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isWinner
                ? cs.primary.withOpacity(0.14)
                : onSurface.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isWinner
                  ? cs.primary.withOpacity(0.28)
                  : onSurface.withOpacity(0.08),
            ),
          ),
          child: Text(
            score == null ? '-' : '$score',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isWinner ? cs.primary : onSurface.withOpacity(0.55),
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }

  // ── Final tab: hero card + bronze/3rd-place card ───────────────────────

  Widget _buildFinalHeroSection(Map<String, List<KnockoutMatch>> rounds) {
    final finalList = rounds['Final'] ?? const <KnockoutMatch>[];
    final finalMatch = finalList.isNotEmpty ? finalList.first : null;

    final thirdList = List<KnockoutMatch>.from(
        rounds['3rd Place'] ?? const <KnockoutMatch>[])
      ..sort((a, b) {
        final aReady =
            (a.homeTeamId != null && a.awayTeamId != null) ? 0 : 1;
        final bReady =
            (b.homeTeamId != null && b.awayTeamId != null) ? 0 : 1;
        final c = aReady.compareTo(bReady);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });
    final thirdMatch = thirdList.isNotEmpty ? thirdList.first : null;

    if (finalMatch == null && thirdMatch == null) {
      return _buildEmptyRoundState();
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _buildRoundSummaryHeader('Final', finalMatch == null ? 0 : 1),
        const SizedBox(height: 16),
        _buildFinalHeroCard(finalMatch),
        if (thirdMatch != null) ...[
          const SizedBox(height: 18),
          _buildBronzeCard(thirdMatch),
        ],
      ],
    );
  }

  Widget _buildFinalHeroCard(KnockoutMatch? match) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    final homeId = match?.homeTeamId;
    final awayId = match?.awayTeamId;

    final homeName =
        _teamName(homeId) ?? (homeId ?? l10n.tr('fixtures_tbd'));
    final awayName =
        _teamName(awayId) ?? (awayId ?? l10n.tr('fixtures_tbd'));
    final homeUrl = _teamImageUrlForId(homeId);
    final awayUrl = _teamImageUrlForId(awayId);

    final info = match != null ? _computeMatchDisplayInfo(match) : null;
    final finished = info?.isFinished ?? false;

    String? championName;
    String? championUrl;
    if (finished && info != null) {
      if (info.isHomeWinner) {
        championName = homeName;
        championUrl = homeUrl;
      } else if (info.isAwayWinner) {
        championName = awayName;
        championUrl = awayUrl;
      }
    }
    // championUrl currently unused beyond computation; reserved for future
    // "champion" crest emphasis without altering existing layout contracts.
    // ignore: unused_local_variable
    final _unusedChampionUrl = championUrl;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            cs.primary.withOpacity(0.26),
            onSurface.withOpacity(0.04),
            cs.secondary.withOpacity(0.22),
          ],
        ),
        border: Border.all(color: onSurface.withOpacity(0.10)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _finalSideColumn(
                  url: homeUrl,
                  name: homeName,
                  score: match?.homeScore,
                  emphasis: info?.isHomeWinner ?? false,
                  alignEnd: false,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.emoji_events_rounded,
                    size: 52,
                    color: finished
                        ? const Color(0xFFFFD54F)
                        : onSurface.withOpacity(0.28),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    championName != null
                        ? championName.toUpperCase()
                        : 'CHAMPION',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: onSurface.withOpacity(0.85),
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: _finalSideColumn(
                  url: awayUrl,
                  name: awayName,
                  score: match?.awayScore,
                  emphasis: info?.isAwayWinner ?? false,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: onSurface.withOpacity(0.10), height: 1),
          const SizedBox(height: 14),
          Text(
            finished
                ? '${championName ?? ''} wins the Final'
                : ((info?.isTBD ?? true)
                    ? 'Awaiting finalists'
                    : 'Final • Not yet played'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: onSurface.withOpacity(0.75),
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _finalSideColumn({
    required String url,
    required String name,
    required int? score,
    required bool emphasis,
    required bool alignEnd,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        _TeamThumb(url: url, size: 46),
        const SizedBox(height: 10),
        Text(
          name.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            color: emphasis ? cs.primary : onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          score == null ? '-' : '$score',
          style: TextStyle(
            color: emphasis ? cs.primary : onSurface.withOpacity(0.85),
            fontWeight: FontWeight.w900,
            fontSize: 30,
          ),
        ),
      ],
    );
  }

  Widget _buildBronzeCard(KnockoutMatch match) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    const bronze = Color(0xFFCD7F32);

    final info = _computeMatchDisplayInfo(match);
    final homeName = _teamName(match.homeTeamId) ??
        (match.homeTeamId ?? l10n.tr('fixtures_tbd'));
    final awayName = _teamName(match.awayTeamId) ??
        (match.awayTeamId ?? l10n.tr('fixtures_tbd'));
    final homeUrl = _teamImageUrlForId(match.homeTeamId);
    final awayUrl = _teamImageUrlForId(match.awayTeamId);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: onSurface.withOpacity(0.035),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bronze.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  size: 16, color: bronze),
              const SizedBox(width: 6),
              const Text(
                '3RD PLACE MATCH',
                style: TextStyle(
                  color: bronze,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _listTeamRow(
              homeUrl, homeName, match.homeScore, info.isHomeWinner),
          const SizedBox(height: 10),
          _listTeamRow(
              awayUrl, awayName, match.awayScore, info.isAwayWinner),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // "BRACKET" (TREE) VIEW — original full-tournament tree, kept intact
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPremiumBracket() {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

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

    for (final rn in roundNames) {
      final list = rounds[rn]!;
      list.sort((a, b) {
        final an = (a.nextMatchId ?? '');
        final bn = (b.nextMatchId ?? '');
        final c1 = an.compareTo(bn);
        if (c1 != 0) return c1;

        final c2 = (a.isSecondLeg ? 1 : 0)
            .compareTo(b.isSecondLeg ? 1 : 0);
        if (c2 != 0) return c2;

        return a.id.compareTo(b.id);
      });
    }

    final thirdPlaceMatches =
        List<KnockoutMatch>.from(rounds['3rd Place'] ??
            const <KnockoutMatch>[])
          ..sort((a, b) {
            final aReady =
                (a.homeTeamId != null && a.awayTeamId != null)
                    ? 0
                    : 1;
            final bReady =
                (b.homeTeamId != null && b.awayTeamId != null)
                    ? 0
                    : 1;
            final c = aReady.compareTo(bReady);
            if (c != 0) return c;
            return a.id.compareTo(b.id);
          });
    final thirdPlaceMatch =
        thirdPlaceMatches.isNotEmpty ? thirdPlaceMatches.first : null;

    final playoffMatches =
        (rounds['Play-off'] ?? const <KnockoutMatch>[]);

    // MODIFIED: Include 'Round of 32' in bracket rounds for FIFA 2026.
    final bracketRounds = <String>[
      for (final rn in const [
        'Round of 32', // World Cup 48-team format
        'Round of 16',
        'Quarter Finals',
        'Semi Finals',
        'Final',
      ])
        if (rounds.containsKey(rn)) rn,
    ];

    final finalList = rounds['Final'] ?? const <KnockoutMatch>[];
    final finalMatch =
        finalList.isNotEmpty ? finalList.first : null;

    final preFinalRounds =
        bracketRounds.where((rn) => rn != 'Final').toList();

    if (preFinalRounds.isEmpty && finalMatch == null) {
      return Center(
        child: Text(
          l10n.tr('knockout_bracket_empty_state'),
          style: TextStyle(
            color: cs.onSurface.withOpacity(0.7),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    final leftByRound = <String, List<KnockoutMatch>>{};
    final rightByRound = <String, List<KnockoutMatch>>{};

    for (final rn in preFinalRounds) {
      final list = List<KnockoutMatch>.from(
          rounds[rn] ?? const <KnockoutMatch>[]);

      final leftCount =
          (list.length == 1) ? 1 : (list.length ~/ 2);
      final left =
          list.sublist(0, math.min(leftCount, list.length));
      final right =
          list.sublist(math.min(leftCount, list.length));

      leftByRound[rn] = left;
      rightByRound[rn] = right.reversed.toList();
    }

    final firstRound =
        preFinalRounds.isNotEmpty ? preFinalRounds.first : null;
    final maxMatches = (firstRound == null)
        ? 1
        : (leftByRound[firstRound]?.length ?? 1);

    final canDraw = _isPowerOfTwo(maxMatches);
    final totalHeight = _totalHeightForMaxMatches(maxMatches);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: discarded_futures
      _ensureUserImagesForTeamIds(<String?>[
        for (final m in _matches) m.homeTeamId,
        for (final m in _matches) m.awayTeamId,
      ]);
    });

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
                      _buildSideBracket(
                        sideTitleRounds: preFinalRounds,
                        byRound: leftByRound,
                        maxMatches: maxMatches,
                        totalHeight: totalHeight,
                        isLeftToRight: true,
                        canDraw: canDraw,
                        textDirection: TextDirection.ltr,
                      ),
                      _buildCenterFinalColumn(
                        maxMatches: maxMatches,
                        totalHeight: totalHeight,
                        finalMatch: finalMatch,
                        canDraw: canDraw,
                      ),
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
            padding: const EdgeInsets.symmetric(
                vertical: 10, horizontal: 16),
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
            for (final m in playoffMatches)
              SizedBox(
                  width: _colWidth, child: _buildMatchCard(m)),
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
                        lineColor: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.35),
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
        ? (_centerY(
                maxMatches: maxMatches, count: 1, index: 0) -
            (_matchCardHeight / 2.0))
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
                padding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 16),
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
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.tr(
                            'knockout_bracket_header_title'),
                        style:
                            theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_matches.length} ${l10n.tr('knockout_bracket_matches_scheduled_suffix')}',
                        style:
                            theme.textTheme.bodySmall?.copyWith(
                          color:
                              cs.onSurface.withOpacity(0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: cs.primary.withOpacity(0.08),
                    border: Border.all(
                        color: cs.primary.withOpacity(0.16)),
                  ),
                  child: Icon(Icons.account_tree_rounded,
                      color: cs.primary, size: 20),
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
                borderRadius:
                    const BorderRadiusDirectional.only(
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

    final roundIndex = _roundIndexForCount(
        maxMatches: maxMatches, count: matches.length);

    return Column(
      children: [
        SizedBox(
          width: _colWidth,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Glass(
              borderRadius: 30,
              padding: const EdgeInsets.symmetric(
                  vertical: 8, horizontal: 14),
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
                  top: _centerY(
                          maxMatches: maxMatches,
                          count: matches.length,
                          index: i) -
                      (_matchCardHeight / 2.0),
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

    final homeName = _teamName(homeId) ??
        (homeId ?? l10n.tr('fixtures_tbd'));
    final awayName = _teamName(awayId) ??
        (awayId ?? l10n.tr('fixtures_tbd'));

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
                  teamId: homeId,
                  name: homeName,
                  score: m?.homeScore,
                  emphasis: isHomeWinner,
                  alignEnd: false,
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primary.withOpacity(0.12),
                    border: Border.all(
                        color: cs.primary.withOpacity(0.18)),
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
                  teamId: awayId,
                  name: awayName,
                  score: m?.awayScore,
                  emphasis: isAwayWinner,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          Divider(
              color: onSurface.withOpacity(0.10), height: 1),
          Row(
            children: [
              Expanded(
                child: Text(
                  finished
                      ? l10n.tr(
                          'admin_knockout_status_completed')
                      : l10n.tr(
                          'admin_knockout_status_pending'),
                  style: TextStyle(
                    color: finished
                        ? cs.primary
                        : onSurface.withOpacity(0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              if (m != null &&
                  finished &&
                  m.homeScore == m.awayScore &&
                  m.tiebreakWinnerTeamId != null)
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
    required String? teamId,
    required String name,
    required int? score,
    required bool emphasis,
    required bool alignEnd,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    final resolvedNameColor =
        emphasis ? cs.primary : onSurface;
    final resolvedScoreColor =
        emphasis ? cs.primary : onSurface.withOpacity(0.85);

    final url = _teamImageUrlForId(teamId);

    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (!alignEnd) ...[
              _TeamThumb(url: url, size: 18),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: alignEnd
                    ? TextAlign.end
                    : TextAlign.start,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: resolvedNameColor,
                  fontWeight: emphasis
                      ? FontWeight.w900
                      : FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            if (alignEnd) ...[
              const SizedBox(width: 8),
              _TeamThumb(url: url, size: 18),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: emphasis
                ? cs.primary.withOpacity(0.12)
                : onSurface.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: emphasis
                  ? cs.primary.withOpacity(0.20)
                  : onSurface.withOpacity(0.10),
            ),
          ),
          child: Text(
            score == null ? '-' : '$score',
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
            padding: const EdgeInsets.symmetric(
                vertical: 8, horizontal: 16),
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
          SizedBox(
              height: _matchCardHeight,
              child: _buildMatchCard(match)),
        ],
      ),
    );
  }

  Widget _buildMatchCard(KnockoutMatch match) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    final homeName = _teamName(match.homeTeamId) ??
        (match.homeTeamId ?? context.l10n.tr('fixtures_tbd'));
    final awayName = _teamName(match.awayTeamId) ??
        (match.awayTeamId ?? context.l10n.tr('fixtures_tbd'));

    final homeUrl = _teamImageUrlForId(match.homeTeamId);
    final awayUrl = _teamImageUrlForId(match.awayTeamId);

    final info = _computeMatchDisplayInfo(match);
    final leftStripeColor = _statusAccentColor(cs, info);

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
                  info.isTBD
                      ? onSurface.withOpacity(0.06)
                      : cs.primary.withOpacity(0.10),
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
                          info.subtitleOverrideOrRoundName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                onSurface.withOpacity(0.55),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      if (match.roundName != 'Play-off')
                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: info.isFinished
                                ? cs.primary.withOpacity(0.14)
                                : onSurface.withOpacity(0.06),
                            borderRadius:
                                BorderRadius.circular(999),
                            border: Border.all(
                                color: onSurface
                                    .withOpacity(0.10)),
                          ),
                          child: Text(
                            info.isFinished
                                ? context.l10n.tr(
                                    'admin_knockout_status_completed')
                                : context.l10n.tr(
                                    'admin_knockout_status_pending'),
                            style: TextStyle(
                              color: info.isFinished
                                  ? cs.primary
                                  : onSurface
                                      .withOpacity(0.55),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildTeamRow(
                    url: homeUrl,
                    name: homeName,
                    score: match.homeScore?.toString() ?? '-',
                    isWinner: info.isHomeWinner,
                  ),
                  const SizedBox(height: 8),
                  Divider(
                      color: onSurface.withOpacity(0.10),
                      height: 1),
                  const SizedBox(height: 8),
                  _buildTeamRow(
                    url: awayUrl,
                    name: awayName,
                    score: match.awayScore?.toString() ?? '-',
                    isWinner: info.isAwayWinner,
                  ),
                  const Spacer(),
                  if (info.footer != null)
                    Align(
                      alignment:
                          AlignmentDirectional.centerStart,
                      child: Text(
                        info.footer!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: info.footerIsWarn
                              ? const Color(0xFFF59E0B)
                              : onSurface.withOpacity(0.60),
                          fontSize: 11,
                          fontWeight: info.footerIsWarn
                              ? FontWeight.w900
                              : FontWeight.w700,
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
              borderRadius:
                  const BorderRadiusDirectional.only(
                topStart: Radius.circular(14),
                bottomStart: Radius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTeamRow({
    required String url,
    required String name,
    required String score,
    required bool isWinner,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    final baseTextColor =
        (score == '-') ? onSurface.withOpacity(0.45) : onSurface;
    final nameColor = isWinner ? cs.primary : baseTextColor;

    return Row(
      children: [
        _TeamThumb(url: url, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: nameColor,
              fontSize: 13,
              fontWeight:
                  isWinner ? FontWeight.w900 : FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isWinner
                ? cs.primary.withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isWinner
                  ? cs.primary.withOpacity(0.18)
                  : Colors.transparent,
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

/// Draws a bracket-style connector linking two feeder matches (top/bottom
/// on the left edge of this painter's box) into a single point on the
/// right edge, used by the "Rounds" list view to visually connect a pair
/// of matches to the next-round match they feed into.
class _BracketConnectorPainter extends CustomPainter {
  const _BracketConnectorPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final midX = size.width / 2;
    final topY = size.height * 0.25;
    final bottomY = size.height * 0.75;
    final midY = size.height / 2;

    final path = Path()
      ..moveTo(0, topY)
      ..lineTo(midX, topY)
      ..lineTo(midX, bottomY)
      ..lineTo(0, bottomY);
    canvas.drawPath(path, paint);
    canvas.drawLine(Offset(midX, midY), Offset(size.width, midY), paint);
  }

  @override
  bool shouldRepaint(covariant _BracketConnectorPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _TeamThumb extends StatelessWidget {
  const _TeamThumb({
    required this.url,
    required this.size,
  });

  final String url;
  final double size;

  bool _looksLikeHttpUrl(String s) {
    final u = s.trim().toLowerCase();
    return u.startsWith('https://') || u.startsWith('http://');
  }

  String _cloudinaryOptimizedUrl(
    String url, {
    int width = 64,
    int height = 64,
  }) {
    final u = url.trim();
    if (u.isEmpty) return u;

    final isCloudinary = u.contains('res.cloudinary.com') &&
        u.contains('/image/upload/');
    if (!isCloudinary) return u;

    final marker = '/image/upload/';
    final idx = u.indexOf(marker);
    if (idx < 0) return u;

    final prefix = u.substring(0, idx + marker.length);
    final suffix = u.substring(idx + marker.length);

    final transforms =
        'f_auto,q_auto,w_$width,h_$height,c_fill,g_auto';

    final parts = suffix.split('/');
    if (parts.isEmpty) return '$prefix$transforms/$suffix';

    final first = parts.first;
    final isVersionOnly = first.startsWith('v') &&
        int.tryParse(first.substring(1)) != null;

    if (!isVersionOnly) {
      if (first.contains('f_auto') ||
          first.contains('q_auto')) return u;
      parts[0] = 'f_auto,q_auto,$first';
      return prefix + parts.join('/');
    }

    return '$prefix$transforms/$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final raw = url.trim();
    final has = raw.isNotEmpty && _looksLikeHttpUrl(raw);

    final px = (size * 3).clamp(48, 96).toInt();
    final d = has
        ? _cloudinaryOptimizedUrl(raw, width: px, height: px)
        : '';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(0.06),
        shape: BoxShape.circle,
        border: Border.all(
            color: cs.onSurface.withOpacity(0.14)),
      ),
      child: ClipOval(
        child: has
            ? Image.network(
                d,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                cacheWidth: px,
                cacheHeight: px,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.emoji_events_outlined,
                  size: size * 0.68,
                  color: cs.onSurface.withOpacity(0.55),
                ),
                loadingBuilder: (context, child, event) {
                  if (event == null) return child;
                  return Icon(
                    Icons.emoji_events_outlined,
                    size: size * 0.68,
                    color: cs.onSurface.withOpacity(0.55),
                  );
                },
              )
            : Icon(
                Icons.emoji_events_outlined,
                size: size * 0.68,
                color: cs.onSurface.withOpacity(0.55),
              ),
      ),
    );
  }
}
