// lib/features/leagues/presentation/knockout_bracket_screen.dart
//
// MODIFIED: Added 'Round of 32' to the bracket round order.
//
// Changes:
// - Added 'Round of 32' to _roundOrder constant list (before 'Round of 16').
// - Added 'Round of 32' to _roundDisplayName() switch case.
// - The rest of the bracket rendering logic handles R32 transparently
//   since it follows the same structural pattern as R16.
// - All other existing code is completely unchanged.

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

  static const double _colWidth = 240;
  static const double _centerWidth = 320;
  static const double _connectorWidth = 56;

  static const double _matchCardHeight = 132;
  static const double _baseGap = 22;
  static const double _unit = _matchCardHeight + _baseGap;

  // MODIFIED: Added 'Round of 32' before 'Round of 16' for World Cup 48-team.
  static const _roundOrder = <String>[
    'Play-off',
    'Round of 32',  // NEW — FIFA 2026 World Cup format
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
      final uid =
          FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      if (uid.isEmpty) {
        if (mounted) context.go('/login');
        return;
      }

      await ConnectivityService.instance.requireOnline(
          timeout: const Duration(seconds: 4));

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
      setState(() {
        _teamsById = {for (final t in teams) t.id: t};
        _teamImageUrls = localImages;
        _matches = koMatches;
        _isLoading = false;
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
        // World Cup 48-team format — no localization key yet, use literal.
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
                      : _buildPremiumBracket(),
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
                  Text(
                    'Couldn't load bracket',
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
        'Round of 32',   // NEW — World Cup 48-team format
        'Round of 16',
        'Quarter Finals',
        'Semi Finals',
        'Final'
      ])
        if (rounds.containsKey(rn)) rn,
    ];

    final finalList =
        rounds['Final'] ?? const <KnockoutMatch>[];
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
      final left = list.sublist(0, math.min(leftCount, list.length));
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
          l10n.tr(
              'knockout_bracket_matches_scheduled_suffix'),
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

  Widget _buildPlayoffSection(
      List<KnockoutMatch> playoffMatches) {
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
                  width: _colWidth,
                  child: _buildMatchCard(m)),
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
      final matches =
          byRound[rn] ?? const <KnockoutMatch>[];
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

    final roundIndex =
        _roundIndexForCount(maxMatches: maxMatches, count: matches.length);

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
        isHomeWinner =
            m.tiebreakWinnerTeamId == m.homeTeamId;
        isAwayWinner =
            m.tiebreakWinnerTeamId == m.awayTeamId;
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
          Divider(color: onSurface.withOpacity(0.10), height: 1),
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
                textAlign:
                    alignEnd ? TextAlign.end : TextAlign.start,
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    final homeName = _teamName(match.homeTeamId) ??
        (match.homeTeamId ?? l10n.tr('fixtures_tbd'));
    final awayName = _teamName(match.awayTeamId) ??
        (match.awayTeamId ?? l10n.tr('fixtures_tbd'));

    final homeUrl = _teamImageUrlForId(match.homeTeamId);
    final awayUrl = _teamImageUrlForId(match.awayTeamId);

    final isTBD =
        match.homeTeamId == null || match.awayTeamId == null;

    bool isHomeWinner = false;
    bool isAwayWinner = false;

    String? subtitle;
    String? footer;

    if (match.roundName == 'Play-off') {
      subtitle = match.isSecondLeg
          ? l10n.tr('admin_knockout_leg2')
          : l10n.tr('admin_knockout_leg1');

      final other = _findOtherLeg(match);
      if (other != null &&
          _isFinished(match) &&
          _isFinished(other)) {
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
          isHomeWinner =
              match.tiebreakWinnerTeamId == match.homeTeamId;
          isAwayWinner =
              match.tiebreakWinnerTeamId == match.awayTeamId;
          footer =
              '${l10n.tr('knockout_bracket_penalties_prefix')}${_teamName(match.tiebreakWinnerTeamId) ?? match.tiebreakWinnerTeamId}';
        } else {
          footer = l10n
              .tr('knockout_bracket_draw_winner_required');
        }
      }
    }

    final leftStripeColor =
        isTBD ? onSurface.withOpacity(0.22) : cs.primary;

    final footerIsWarn = footer ==
            l10n.tr(
                'knockout_bracket_draw_winner_required') ||
        footer ==
            l10n.tr(
                'knockout_bracket_aggregate_tied_penalties_required');

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
                  isTBD
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _isFinished(match)
                                ? cs.primary.withOpacity(0.14)
                                : onSurface.withOpacity(0.06),
                            borderRadius:
                                BorderRadius.circular(999),
                            border: Border.all(
                                color:
                                    onSurface.withOpacity(0.10)),
                          ),
                          child: Text(
                            _isFinished(match)
                                ? context.l10n.tr(
                                    'admin_knockout_status_completed')
                                : context.l10n.tr(
                                    'admin_knockout_status_pending'),
                            style: TextStyle(
                              color: _isFinished(match)
                                  ? cs.primary
                                  : onSurface.withOpacity(0.55),
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
                    score: match.homeScore?.toString() ?? "-",
                    isWinner: isHomeWinner,
                  ),
                  const SizedBox(height: 8),
                  Divider(
                      color: onSurface.withOpacity(0.10),
                      height: 1),
                  const SizedBox(height: 8),
                  _buildTeamRow(
                    url: awayUrl,
                    name: awayName,
                    score: match.awayScore?.toString() ?? "-",
                    isWinner: isAwayWinner,
                  ),
                  const Spacer(),
                  if (footer != null)
                    Align(
                      alignment:
                          AlignmentDirectional.centerStart,
                      child: Text(
                        footer!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: footerIsWarn
                              ? const Color(0xFFF59E0B)
                              : onSurface.withOpacity(0.60),
                          fontSize: 11,
                          fontWeight: footerIsWarn
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
        (score == "-") ? onSurface.withOpacity(0.45) : onSurface;
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
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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

  String _cloudinaryOptimizedUrl(String url,
      {int width = 64, int height = 64}) {
    final u = url.trim();
    if (u.isEmpty) return u;

    final isCloudinary =
        u.contains('res.cloudinary.com') &&
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
    final d =
        has ? _cloudinaryOptimizedUrl(raw, width: px, height: px) : '';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(0.06),
        shape: BoxShape.circle,
        border:
            Border.all(color: cs.onSurface.withOpacity(0.14)),
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
                  return Icon(Icons.emoji_events_outlined,
                      size: size * 0.68,
                      color: cs.onSurface.withOpacity(0.55));
                },
              )
            : Icon(Icons.emoji_events_outlined,
                size: size * 0.68,
                color: cs.onSurface.withOpacity(0.55)),
      ),
    );
  }
}