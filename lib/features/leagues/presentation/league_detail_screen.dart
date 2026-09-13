// lib/features/leagues/presentation/league_detail_screen.dart
//
// MODIFIED (World Cup support):
// 1) Added World Cup format pill in _overviewCard (FIFA 2022 vs FIFA 2026).
// 2) Extended _quickActions to treat World Cup as a knockout-capable format.
// 3) Added organizer action: "Generate World Cup Knockouts".
// 4) Added _generateWorldCupKnockouts() which computes group standings (with FIFA tie-breakers)
//    and seeds the correct bracket (R16 for 32 teams, R32 for 48 teams).
// 5) Imported league_settings.dart for WorldCupFormat access.
//
// MODIFIED (Football Category support):
// 6) Imported football_category.dart.
// 7) Added a backward-compatible football category pill in _overviewCard.
//
// IMPORTANT:
// - No existing flows were removed.
// - Classic / UCL Group / UCL Swiss logic remains unchanged.
// - World Cup KO generation is an additive path only.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../highlights/data/highlights_feed_repository_firebase.dart';
import '../../highlights/domain/match_highlight.dart';
import '../../highlights/presentation/league_highlights_section.dart';
import '../../social/ui/widgets/glass_announcement.dart';
import '../data/leagues_repository_local.dart';
import '../data/models/reward_model.dart';
import '../data/services/reward_firestore_service.dart';
import '../domain/logic/tournament_controller.dart';
import '../domain/standings/standings.dart';
import '../domain/standings/standings_calculator.dart';
import '../models/fixture_match.dart';
import '../models/football_category.dart';
import '../models/knockout_match.dart';
import '../models/league.dart';
import '../models/league_announcement.dart';
import '../models/league_format.dart';
import '../models/league_settings.dart';
import '../models/membership.dart';
import '../models/team.dart';
import 'screens/edit_league_rewards_screen.dart';
import 'screens/league_rewards_screen.dart';
import 'widgets/join_league_mode_sheet.dart';
import 'widgets/reward_card.dart';

class _L10nException implements Exception {
  final String key;
  const _L10nException(this.key);

  @override
  String toString() => key;
}

class LeagueDetailScreen extends ConsumerStatefulWidget {
  final String leagueId;

  const LeagueDetailScreen({
    super.key,
    required this.leagueId,
  });

  @override
  ConsumerState<LeagueDetailScreen> createState() => _LeagueDetailScreenState();
}

class _LeagueDetailScreenState extends ConsumerState<LeagueDetailScreen> {
  late final LocalLeaguesRepository _repo;
  late final PreferencesService _prefs;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final RewardFirestoreService _rewardsService = RewardFirestoreService();

  late final HighlightsFeedRepositoryFirebase _highlightsFeedRepo;
  late final Stream<List<MatchHighlight>> _leagueHighlightsStream;

  late Future<Map<String, dynamic>> _screenFuture;

  int? _lastViewedRound;
  static String _lastRoundKey(String leagueId) => 'ui_last_round_$leagueId';

  int _lastSeenAnnMs = 0;
  static String _lastSeenAnnKey(String leagueId) =>
      'ui_last_seen_ann_$leagueId';

  final ScrollController _annScrollController = ScrollController();
  Timer? _annScrollTimer;
  int _annLastCount = 0;

  static const Color _premiumAmber = Color(0xFFF59E0B);
  static const Color _premiumViolet = Color(0xFF8B5CF6);
  static const Color _premiumSky = Color(0xFF38BDF8);
  static const Color _premiumTeal = Color(0xFF2DD4BF);

  bool _joining = false;

  // ── cached result so hot-reloads are instant ──────────────────────────────
  Map<String, dynamic>? _cachedData;

  @override
  void initState() {
    super.initState();
    _prefs = ref.read(prefsServiceProvider);
    _repo = LocalLeaguesRepository(_prefs);

    final rawRound = _prefs.getString(_lastRoundKey(widget.leagueId));
    _lastViewedRound = int.tryParse((rawRound ?? '').trim());

    _lastSeenAnnMs = _prefs.getInt(_lastSeenAnnKey(widget.leagueId)) ?? 0;

    _highlightsFeedRepo = HighlightsFeedRepositoryFirebase();
    _leagueHighlightsStream = _highlightsFeedRepo.watchLeagueHighlights(
      leagueId: widget.leagueId,
      limit: 10,
    );

    _screenFuture = _loadData();
  }

  @override
  void dispose() {
    _annScrollTimer?.cancel();
    _annScrollController.dispose();
    super.dispose();
  }

  void _reloadScreen() {
    if (!mounted) return;
    setState(() {
      _cachedData = null;
      _screenFuture = _loadData();
    });
  }

  Color _baseToastBg(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? const Color(0xFF101522)
        : const Color(0xFFF8FBFF);
  }

  void _toast(
    String msg, {
    Color? bg,
    Color? fg,
    IconData? icon,
  }) {
    if (!mounted) return;

    final theme = Theme.of(context);

    final resolvedBg = bg ?? _baseToastBg(theme);
    final resolvedFg = fg ??
        (theme.brightness == Brightness.dark
            ? Colors.white
            : AppTheme.primaryText(theme.brightness));

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: resolvedBg,
        margin: const EdgeInsets.all(12),
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: resolvedFg, size: 18),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                msg,
                style: TextStyle(
                    color: resolvedFg, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _toastOk(String msg) {
    final theme = Theme.of(context);
    final baseBg = _baseToastBg(theme);
    final accent = AppTheme.limeAccentDark;
    _toast(
      msg,
      bg: Color.alphaBlend(accent.withOpacity(0.16), baseBg),
      fg: accent,
      icon: Icons.check_circle_outline,
    );
  }

  void _toastWarn(String msg) {
    final theme = Theme.of(context);
    final baseBg = _baseToastBg(theme);
    _toast(
      msg,
      bg: Color.alphaBlend(_premiumAmber.withOpacity(0.16), baseBg),
      fg: _premiumAmber,
      icon: Icons.warning_amber_rounded,
    );
  }

  void _toastErr(String msg) {
    final theme = Theme.of(context);
    final err = Theme.of(context).colorScheme.error;
    final baseBg = _baseToastBg(theme);
    _toast(
      msg,
      bg: Color.alphaBlend(err.withOpacity(0.14), baseBg),
      fg: err,
      icon: Icons.error_outline,
    );
  }

  Future<void> _persistRound(int round) async {
    _lastViewedRound = round;
    if (mounted) setState(() {});
    await _prefs.setString(_lastRoundKey(widget.leagueId), '$round');
  }

  Future<void> _markAnnouncementsSeen(int ms) async {
    _lastSeenAnnMs = ms;
    await _prefs.setInt(_lastSeenAnnKey(widget.leagueId), ms);
  }

  void _ensureAnnounceAutoScroll(int count) {
    if (count <= 1) {
      _annScrollTimer?.cancel();
      _annScrollTimer = null;
      _annLastCount = count;
      return;
    }

    if (_annLastCount == count && _annScrollTimer != null) return;

    _annLastCount = count;
    _annScrollTimer?.cancel();

    _annScrollTimer =
        Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (!_annScrollController.hasClients) return;
      final maxScroll = _annScrollController.position.maxScrollExtent;
      if (maxScroll <= 0) return;

      final current = _annScrollController.offset;
      final next = current + 1;
      if (next >= maxScroll) {
        _annScrollController.jumpTo(0);
      } else {
        _annScrollController.jumpTo(next);
      }
    });
  }

  int _intFrom(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  /// Loads announcements – tries cache first, then server with short timeout.
  Future<List<LeagueAnnouncement>> _loadAnnouncements(
      String leagueId) async {
    try {
      // Try cache first for speed
      final cacheSnap = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('announcements')
          .orderBy('createdAtMs', descending: true)
          .limit(30)
          .get(const GetOptions(source: Source.cache));

      if (cacheSnap.docs.isNotEmpty) {
        // Fire-and-forget background refresh
        _firestore
            .collection('leagues')
            .doc(leagueId)
            .collection('announcements')
            .orderBy('createdAtMs', descending: true)
            .limit(30)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 6))
            .then((_) {})
            .ignore();

        return _parseAnnouncements(cacheSnap.docs);
      }
    } catch (_) {
      // Cache miss – fall through to server
    }

    // No cache – fetch from server with a short timeout
    final snap = await _firestore
        .collection('leagues')
        .doc(leagueId)
        .collection('announcements')
        .orderBy('createdAtMs', descending: true)
        .limit(30)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 6));

    return _parseAnnouncements(snap.docs);
  }

  List<LeagueAnnouncement> _parseAnnouncements(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final out = <LeagueAnnouncement>[];
    for (final d in docs) {
      final data = d.data();
      data['createdAtMs'] =
          _intFrom(data['createdAtMs'], fallback: 0);
      data['id'] =
          (data['id'] is String && (data['id'] as String).trim().isNotEmpty)
              ? data['id']
              : d.id;
      try {
        out.add(LeagueAnnouncement.fromMap(data));
      } catch (_) {}
    }
    return out;
  }

  /// Loads space/current – tries cache first.
  Future<Map<String, dynamic>?> _loadSpaceCurrent(
      String leagueId) async {
    try {
      final cacheDoc = await _firestore
          .collection('leagues')
          .doc(leagueId)
          .collection('space')
          .doc('current')
          .get(const GetOptions(source: Source.cache));

      if (cacheDoc.exists && cacheDoc.data() != null) {
        // Background refresh
        _firestore
            .collection('leagues')
            .doc(leagueId)
            .collection('space')
            .doc('current')
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 5))
            .then((_) {})
            .ignore();

        return <String, dynamic>{...cacheDoc.data()!};
      }
    } catch (_) {}

    // No cache – server fetch with shorter timeout
    final doc = await _firestore
        .collection('leagues')
        .doc(leagueId)
        .collection('space')
        .doc('current')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 5));

    if (!doc.exists || doc.data() == null) return null;
    return <String, dynamic>{...doc.data()!};
  }

  Future<void> _joinLeagueFromDetails(League league) async {
    final uid =
        FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      _toastErr('Please sign in and try again.');
      return;
    }
    if (_joining) return;

    final selectedMode = await showJoinLeagueModeSheet(
      context,
      league: league,
      title: 'Join League',
    );

    if (selectedMode == null) return;

    setState(() => _joining = true);
    try {
      await _repo.joinLeagueDirect(
        leagueId: league.id,
        mode: selectedMode,
      );

      if (!mounted) return;
      _toastOk(
        selectedMode == LeagueJoinMode.viewer
            ? 'League added to your list as viewer.'
            : 'Successfully joined league.',
      );
      _reloadScreen();
    } catch (e) {
      _toastErr(
        UserFriendlyError.toMessage(
            e is Object ? e : Exception('unknown')),
      );
    } finally {
      if (mounted) {
        setState(() => _joining = false);
      }
    }
  }

  Future<Map<String, dynamic>> _loadData() async {
    // Return cache instantly on soft reloads triggered by navigation
    if (_cachedData != null) return _cachedData!;

    final authUid =
        (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (authUid.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/login');
      });
      throw FirebaseAuthException(code: 'unauthenticated');
    }

    // Run connectivity check in parallel with data fetching –
    // don't block the whole load on it.
    final connectivityFuture = ConnectivityService.instance
        .requireOnline(timeout: const Duration(seconds: 3))
        .catchError((_) {});

    // ── Fire ALL repo calls simultaneously ───────────────────────────────────
    final results = await Future.wait([
      _repo
          .getLeagueById(widget.leagueId)
          .timeout(const Duration(seconds: 8)),
      _repo
          .getMatches(widget.leagueId)
          .timeout(const Duration(seconds: 10)),
      _repo
          .getTeams(widget.leagueId)
          .timeout(const Duration(seconds: 8)),
      _repo
          .getKnockoutMatches(widget.leagueId)
          .timeout(const Duration(seconds: 10)),
      _repo
          .getMembership(leagueId: widget.leagueId, userId: authUid)
          .timeout(const Duration(seconds: 6)),
    ]);

    await connectivityFuture;

    final league = results[0] as League?;
    if (league == null) {
      throw const _L10nException('leagues_error_not_found_local_storage');
    }

    final fixtures = results[1] as List<FixtureMatch>;
    final teams = results[2] as List<Team>;
    final knockouts = results[3] as List<KnockoutMatch>;
    final membership = results[4] as Membership?;

    // ── Announcements & space in parallel (non-blocking on main data) ────────
    final List<dynamic> extras = await Future.wait([
      _loadAnnouncements(widget.leagueId),
      _loadSpaceCurrent(widget.leagueId),
    ]);

    final announcements = extras[0] as List<LeagueAnnouncement>;
    final space = extras[1] as Map<String, dynamic>?;

    final teamNames = {for (final t in teams) t.id: t.name};
    final teamImageUrls = {
      for (final t in teams) t.id: t.teamImageUrl.trim()
    };
    final teamsById = {for (final t in teams) t.id: t};

    _cachedData = {
      'league': league,
      'fixtures': fixtures,
      'teams': teams,
      'teamsById': teamsById,
      'teamNames': teamNames,
      'teamImageUrls': teamImageUrls,
      'currentUserId': authUid,
      'membership': membership,
      'knockouts': knockouts,
      'announcements': announcements,
      'space': space,
    };

    return _cachedData!;
  }

  List<FixtureMatch> _sortedSchedule(List<FixtureMatch> fixtures) {
    final sorted = fixtures.toList()
      ..sort((a, b) {
        final r = a.roundNumber.compareTo(b.roundNumber);
        if (r != 0) return r;
        final s = a.sortIndex.compareTo(b.sortIndex);
        if (s != 0) return s;
        return a.updatedAtMs.compareTo(b.updatedAtMs);
      });
    return sorted;
  }

  List<int> _allRounds(List<FixtureMatch> sorted) {
    final rounds =
        sorted.map((m) => m.roundNumber).toSet().toList()..sort();
    return rounds;
  }

  List<FixtureMatch> _computeUpcomingUnplayed({
    required List<FixtureMatch> sortedAll,
    required int selectedRound,
    int limit = 8,
  }) {
    final unplayed = sortedAll.where((m) => !m.isPlayed).toList();
    if (unplayed.isEmpty) return [];

    final roundsWithUnplayed =
        unplayed.map((m) => m.roundNumber).toSet().toList()..sort();

    int effectiveRound = selectedRound;
    if (!roundsWithUnplayed.contains(effectiveRound)) {
      final next =
          roundsWithUnplayed.where((r) => r > selectedRound).toList();
      effectiveRound =
          next.isNotEmpty ? next.first : roundsWithUnplayed.first;
    }

    if (effectiveRound != selectedRound) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _persistRound(effectiveRound);
      });
    }

    final filtered = sortedAll
        .where((m) => !m.isPlayed && m.roundNumber >= effectiveRound)
        .toList();
    if (filtered.length <= limit) return filtered;
    return filtered.take(limit).toList();
  }

  Future<void> _onStartSpace(
      League league, String currentUserId) async {
    try {
      if (currentUserId.trim().isEmpty) {
        _toastErr('Please sign in and try again.');
        return;
      }

      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));

      final now = DateTime.now().millisecondsSinceEpoch;

      await _firestore
          .collection('leagues')
          .doc(league.id)
          .collection('space')
          .doc('current')
          .set(
        {
          'leagueId': league.id,
          'hostUserId': currentUserId,
          'title':
              '${league.name} ${context.l10n.tr('league_details_space_title_suffix')}',
          'isLive': true,
          'startedAtMs': now,
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      _reloadScreen();
      _toastOk(
          context.l10n.tr('league_details_space_started'));
    } catch (e) {
      _toastErr(
        UserFriendlyError.toMessage(
            e is Object ? e : Exception('unknown')),
      );
    }
  }

  Future<void> _onEndSpace(League league) async {
    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));

      final now = DateTime.now().millisecondsSinceEpoch;

      await _firestore
          .collection('leagues')
          .doc(league.id)
          .collection('space')
          .doc('current')
          .set(
        {
          'isLive': false,
          'endedAtMs': now,
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      _reloadScreen();
      _toastOk(context.l10n.tr('league_details_space_ended'));
    } catch (e) {
      _toastErr(
        UserFriendlyError.toMessage(
            e is Object ? e : Exception('unknown')),
      );
    }
  }

  Future<void> _onOpenSpace(League league) async {
    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));
      if (!mounted) return;
      await context.push('/leagues/${league.id}/space');
      if (!mounted) return;
      _reloadScreen();
    } catch (e) {
      _toastErr(
        UserFriendlyError.toMessage(
            e is Object ? e : Exception('unknown')),
      );
    }
  }

  Future<void> _onOpenLeagueChatroom(League league) async {
    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));
      if (!mounted) return;
      await context.push('/leagues/${widget.leagueId}/chat');
    } catch (e) {
      _toastErr(
        UserFriendlyError.toMessage(
            e is Object ? e : Exception('unknown')),
      );
    }
  }

  void _openRewardsViewer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            LeagueRewardsScreen(leagueId: widget.leagueId),
      ),
    );
  }

  Future<void> _openRewardsManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            EditLeagueRewardsScreen(leagueId: widget.leagueId),
      ),
    );
    if (!mounted) return;
    _reloadScreen();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final isWide = MediaQuery.of(context).size.width > 600;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('league_details_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: l10n.tr('common_refresh'),
            onPressed: () {
              _reloadScreen();
              _toastOk(l10n.tr('common_done'));
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _screenFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState ==
                      ConnectionState.waiting &&
                  _cachedData == null) {
                return Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.limeAccentDark,
                  ),
                );
              }

              if (snapshot.hasError && _cachedData == null) {
                final err = snapshot.error;
                final message = (err is _L10nException)
                    ? l10n.tr(err.key)
                    : UserFriendlyError.toMessage(err is Object
                        ? err
                        : Exception('unknown'));

                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color:
                              Theme.of(context).colorScheme.error,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${l10n.tr('common_error_prefix')}: $message',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color:
                                AppTheme.secondaryText(brightness),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (kDebugMode && err != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            err.runtimeType.toString(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color:
                                  AppTheme.secondaryText(brightness),
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _reloadScreen,
                          child: Text(
                            l10n.tr('common_retry'),
                            style: const TextStyle(
                              color: AppTheme.limeAccentDark,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final data =
                  snapshot.data ?? _cachedData;
              if (data == null) return const SizedBox.shrink();

              final league = data['league'] as League;
              final fixtures =
                  data['fixtures'] as List<FixtureMatch>;
              final teams = data['teams'] as List<Team>;
              final teamsById =
                  data['teamsById'] as Map<String, Team>;
              final teamNames =
                  data['teamNames'] as Map<String, String>;
              final teamImageUrls =
                  data['teamImageUrls'] as Map<String, String>;
              final currentUserId =
                  data['currentUserId'] as String;
              final membership =
                  data['membership'] as Membership?;
              final knockouts =
                  data['knockouts'] as List<KnockoutMatch>;
              final announcements = data['announcements']
                  as List<LeagueAnnouncement>;
              final space =
                  data['space'] as Map<String, dynamic>?;

              final sorted = _sortedSchedule(fixtures);
              final rounds = _allRounds(sorted);
              final selectedRound = (_lastViewedRound != null &&
                      rounds.contains(_lastViewedRound))
                  ? _lastViewedRound!
                  : (rounds.isEmpty ? 1 : rounds.first);

              final upcoming = _computeUpcomingUnplayed(
                sortedAll: sorted,
                selectedRound: selectedRound,
                limit: 8,
              );

              int latestAnnMs = 0;
              if (announcements.isNotEmpty) {
                latestAnnMs = announcements
                    .map((a) => a.createdAtMs)
                    .reduce(max);
              }
              final hasUnreadAnnouncements = announcements
                      .isNotEmpty &&
                  latestAnnMs > _lastSeenAnnMs;

              if (hasUnreadAnnouncements) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) {
                  _markAnnouncementsSeen(latestAnnMs);
                });
              }

              _ensureAnnounceAutoScroll(announcements.length);

              final isOwnerByMembership =
                  membership?.role == LeagueRole.organizer;
              final isOwnerByLeague =
                  league.organizerUid.trim().isNotEmpty &&
                      league.organizerUid.trim() ==
                          currentUserId.trim();
              final isOwner =
                  isOwnerByMembership || isOwnerByLeague;

              const canChat = true;
              final spaceLive = space?['isLive'] == true;
              final isJoined = membership != null || isOwner;

              final matchesById = {
                for (final m in fixtures) m.id: m
              };

              return ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: isWide ? 600 : 500),
                child: RefreshIndicator(
                  onRefresh: () async => _reloadScreen(),
                  color: AppTheme.limeAccentDark,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    children: [
                      _overviewCard(context, league, isOwner),
                      if (!isJoined) ...[
                        const SizedBox(height: 16),
                        _joinLeagueCard(context, league),
                      ],
                      if (announcements.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _announcementsCard(
                          context,
                          announcements,
                          hasUnreadAnnouncements,
                        ),
                      ],
                      const SizedBox(height: 16),
                      _quickActions(
                        context,
                        league,
                        isOwner,
                        canChat,
                        fixtures,
                        teams,
                        knockouts,
                        spaceLive,
                        currentUserId,
                      ),
                      const SizedBox(height: 16),
                      _rewardsPreviewCard(
                          context, league, isOwner),
                      const SizedBox(height: 16),
                      LeagueHighlightsSection(
                        leagueId: widget.leagueId,
                        highlightsStream: _leagueHighlightsStream,
                        matchesById: matchesById,
                        teamsById: teamsById,
                        limitLabel: 'Latest highlights',
                      ),
                      const SizedBox(height: 16),
                      _upcomingMatchesCard(
                        context,
                        fixtures: upcoming,
                        names: teamNames,
                        teamImageUrls: teamImageUrls,
                        rounds: rounds,
                        selectedRound: selectedRound,
                        onRoundSelected: (r) => _persistRound(r),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _joinLeagueCard(BuildContext context, League league) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Glass(
      padding: const EdgeInsets.all(20),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.login_rounded,
                  color: AppTheme.limeAccentDark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Join This League',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryText(brightness),
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            league.isInsideMasterLeague
                ? 'This competition belongs to a master league workspace. You can join directly from here as participant or viewer.'
                : 'You have not joined this league yet. Join now as participant or add it to your list as viewer.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
              ),
              onPressed: _joining
                  ? null
                  : () => _joinLeagueFromDetails(league),
              icon: _joining
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.darkText,
                      ),
                    )
                  : const Icon(Icons.login_rounded),
              label: Text(
                _joining ? 'Joining...' : 'Join League',
                style:
                    const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          if (league.isInsideMasterLeague &&
              league.masterLeagueId.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.push(
                    '/master-leagues/${league.masterLeagueId}'),
                icon: const Icon(Icons.hub_rounded),
                label: const Text(
                  'Open Workspace',
                  style:
                      TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _overviewCard(
      BuildContext context, League league, bool isOwner) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final settings = league.settings;

    final rulePills = <Widget>[
      _pill(
        league.isPrivate
            ? l10n.tr('league_details_private')
            : l10n.tr('league_details_public'),
        AppTheme.limeAccentDark,
      ),
      _pill(
        '${league.maxTeams} ${l10n.tr('league_details_teams_max_suffix')}',
        _premiumAmber,
      ),
      _pill(league.region, _premiumViolet),
      if (league.viewerCapacity > 0)
        _pill('${league.viewerCapacity} Viewers', _premiumTeal),
      _pill(
        settings.doubleRoundRobin
            ? l10n.tr('league_details_double_rr')
            : l10n.tr('league_details_single_rr'),
        _premiumSky,
      ),
    ];

    // ── NEW: Football category pill (backward-compatible — resolves to
    // Local Football for older documents that predate this field). ────────
    rulePills.add(
      _pill(league.footballCategory.badgeLabel, AppTheme.limeAccentDark),
    );

    if (league.format == LeagueFormat.uclGroup) {
      rulePills.add(
        _pill(
          '${l10n.tr('league_details_group_size_prefix')} ${settings.groupSize}',
          _premiumTeal,
        ),
      );
    }
    if (league.format == LeagueFormat.uclSwiss) {
      rulePills.add(
        _pill(
          '${l10n.tr('league_details_swiss_rounds_prefix')} ${settings.swissRounds}',
          _premiumTeal,
        ),
      );
    }

    // ── NEW: World Cup format pill (FIFA 2022 vs FIFA 2026) ──────────────────
    if (league.format == LeagueFormat.worldCup) {
      final wc = league.worldCupFormat;
      rulePills.add(
        _pill(
          wc == WorldCupFormat.fifa2026
              ? 'FIFA 2026 • 48 Teams'
              : 'FIFA 2022 • 32 Teams',
          _premiumAmber,
        ),
      );
    }

    final desc = league.description.trim();

    return Glass(
      padding: const EdgeInsets.all(20),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LeagueHero(
            leagueImageUrl: league.leagueImageUrl,
            sponsorImageUrl: league.sponsorImageUrl,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  league.name,
                  style:
                      theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryText(brightness),
                  ),
                ),
              ),
              if (isOwner)
                Tooltip(
                  message: l10n
                      .tr('league_details_organiser_tooltip'),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: brightness == Brightness.dark
                          ? AppTheme.limeAccentDark
                              .withOpacity(0.10)
                          : const Color(0xFFECFCCB),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified_user,
                      color: AppTheme.limeAccentDark,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${league.format.displayName} • ${league.season}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.secondaryText(brightness),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (league.isInsideMasterLeague) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(
                    'Master League Competition', _premiumAmber),
                OutlinedButton.icon(
                  onPressed: () => context.push(
                      '/master-leagues/${league.masterLeagueId}'),
                  icon:
                      const Icon(Icons.hub_rounded, size: 16),
                  label: const Text(
                    'Open Workspace',
                    style: TextStyle(
                        fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ],
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              desc,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.secondaryText(brightness),
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Wrap(spacing: 8, runSpacing: 8, children: rulePills),
        ],
      ),
    );
  }

  Widget _announcementsCard(
    BuildContext context,
    List<LeagueAnnouncement> anns,
    bool hasUnread,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final sorted = anns.toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    final formatter = DateFormat('MMM d • HH:mm');

    return Glass(
      padding: const EdgeInsets.all(20),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.tr(
                    'league_details_announcements_title'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.primaryText(brightness),
                  fontSize: 16,
                ),
              ),
              if (hasUnread) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .error
                        .withOpacity(0.90),
                    borderRadius:
                        BorderRadius.circular(999),
                  ),
                  child: Text(
                    l10n.tr('league_details_new_badge'),
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onError,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: ListView.separated(
              controller: _annScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: sorted.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final a = sorted[index];
                final timeStr = formatter.format(
                    DateTime.fromMillisecondsSinceEpoch(
                        a.createdAtMs));
                return GlassAnnouncement(
                  title: a.title,
                  message: a.message,
                  time: timeStr,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _rewardsPreviewCard(
      BuildContext context, League league, bool isOwner) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Glass(
      padding: const EdgeInsets.all(20),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard_outlined,
                  size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Rewards',
                  style:
                      theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryText(brightness),
                    fontSize: 16,
                  ),
                ),
              ),
              TextButton(
                onPressed: _openRewardsViewer,
                child: const Text(
                  'View all',
                  style: TextStyle(
                    color: AppTheme.limeAccentDark,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              if (isOwner) ...[
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _openRewardsManager,
                  icon: const Icon(Icons.edit_outlined,
                      size: 18),
                  label: const Text(
                    'Manage',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          FutureBuilder<bool>(
            future:
                _rewardsService.hasRewards(leagueId: league.id),
            builder: (context, hasSnap) {
              final hasRewards = hasSnap.data == true;

              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                child: hasSnap.connectionState !=
                        ConnectionState.done
                    ? const Center(
                        key: ValueKey('loading'),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              vertical: 18),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppTheme.limeAccentDark,
                            ),
                          ),
                        ),
                      )
                    : (!hasRewards
                        ? Container(
                            key: const ValueKey('empty'),
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 12),
                            decoration: BoxDecoration(
                              color: AppTheme
                                  .searchBackground(brightness),
                              borderRadius:
                                  BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme
                                    .searchOutline(brightness),
                              ),
                            ),
                            child: Text(
                              'No rewards available',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppTheme
                                    .secondaryText(brightness),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : StreamBuilder<List<RewardModel>>(
                            key: const ValueKey('list'),
                            stream: _rewardsService.streamRewards(
                                leagueId: league.id),
                            builder: (context, snap) {
                              if (snap.hasError) {
                                return Container(
                                  width: double.infinity,
                                  padding:
                                      const EdgeInsets.symmetric(
                                          vertical: 12,
                                          horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error
                                        .withOpacity(0.10),
                                    borderRadius:
                                        BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error
                                          .withOpacity(0.18),
                                    ),
                                  ),
                                  child: Text(
                                    'Failed to load rewards',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                );
                              }

                              final all = snap.data ??
                                  const <RewardModel>[];
                              final preview = all
                                  .take(3)
                                  .toList(growable: false);

                              return TweenAnimationBuilder<
                                  double>(
                                tween: Tween<double>(
                                    begin: 0.96, end: 1),
                                duration: const Duration(
                                    milliseconds: 240),
                                curve: Curves.easeOutCubic,
                                builder:
                                    (context, scale, child) =>
                                        Transform.scale(
                                            scale: scale,
                                            child: child),
                                child: Column(
                                  children: [
                                    for (final r in preview)
                                      RewardCard(
                                        reward: r,
                                        onTap: _openRewardsViewer,
                                      ),
                                    if (all.length >
                                        preview.length)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(
                                                top: 6),
                                        child: Align(
                                          alignment:
                                              AlignmentDirectional
                                                  .center,
                                          child: Text(
                                            '+${all.length - preview.length} more',
                                            style: TextStyle(
                                              color: AppTheme
                                                  .secondaryText(
                                                      brightness),
                                              fontWeight:
                                                  FontWeight.w800,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          )),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _quickActions(
    BuildContext context,
    League league,
    bool isOwner,
    bool canChat,
    List<FixtureMatch> fixtures,
    List<Team> teams,
    List<KnockoutMatch> knockouts,
    bool spaceLive,
    String currentUserId,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final isSwiss = league.format == LeagueFormat.uclSwiss;
    final isGroup = league.format == LeagueFormat.uclGroup;
    final isWorldCup = league.format == LeagueFormat.worldCup; // NEW
    final hasKnockouts = knockouts.isNotEmpty;

    void showNeedKnockoutsSnack() =>
        _toastWarn(l10n.tr('league_details_need_knockouts_first'));

    return Glass(
      padding: const EdgeInsets.all(20),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tr('league_details_menu_title'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryText(brightness),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          _buildLeagueSpaceRow(
            context,
            league,
            isOwner,
            spaceLive,
            currentUserId,
          ),
          if (canChat) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: AppTheme.cardBorder(brightness)),
                  foregroundColor: AppTheme.limeAccentDark,
                  padding: const EdgeInsets.symmetric(
                      vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () =>
                    _onOpenLeagueChatroom(league),
                icon: const Icon(Icons.forum_outlined),
                label: const Text(
                  'League Chatroom',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.list_alt,
                  label:
                      l10n.tr('league_details_fixtures'),
                  onTap: () async {
                    await context.push(
                        '/leagues/${widget.leagueId}/fixtures');
                    if (!mounted) return;
                    _reloadScreen();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  icon: Icons.leaderboard,
                  label: l10n
                      .tr('league_details_standings'),
                  onTap: () => context.push(
                      '/leagues/${widget.leagueId}/standings'),
                ),
              ),
            ],
          ),
          if (!isOwner) ...[
            const SizedBox(height: 12),
            if (hasKnockouts)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.limeAccent,
                    foregroundColor: AppTheme.darkText,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12)),
                  ),
                  onPressed: () => context.push(
                      '/leagues/${widget.leagueId}/knockout'),
                  icon: const Icon(
                      Icons.emoji_events_rounded),
                  label: Text(
                    l10n.tr(
                        'league_details_view_knockout_bracket'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12),
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    vertical: 14, horizontal: 12),
                decoration: BoxDecoration(
                  color:
                      AppTheme.searchBackground(brightness),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color:
                        AppTheme.searchOutline(brightness),
                  ),
                ),
                child: Text(
                  l10n.tr(
                      'league_details_need_knockouts_first'),
                  style: TextStyle(
                    color:
                        AppTheme.secondaryText(brightness),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  vertical: 12, horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.searchBackground(brightness),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.searchOutline(brightness),
                ),
              ),
              child: Text(
                l10n.tr(
                    'league_details_view_only_banner'),
                style: TextStyle(
                  color: AppTheme.secondaryText(brightness),
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          if (isOwner) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.limeAccent,
                  foregroundColor: AppTheme.darkText,
                  padding: const EdgeInsets.symmetric(
                      vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.edit_note),
                label: Text(
                  l10n.tr(
                      'league_details_manage_league_scores'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900),
                ),
                onPressed: () async {
                  await context.push(
                      '/leagues/${widget.leagueId}/admin-scores');
                  if (!mounted) return;
                  _reloadScreen();
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: AppTheme.cardBorder(brightness)),
                  foregroundColor: AppTheme.limeAccentDark,
                  padding: const EdgeInsets.symmetric(
                      vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.settings),
                label: Text(
                  l10n.tr(
                      'league_details_league_settings_admin'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12),
                ),
                onPressed: () => context
                    .push('/leagues/${widget.leagueId}/admin'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: AppTheme.cardBorder(brightness)),
                  foregroundColor: AppTheme.limeAccentDark,
                  padding: const EdgeInsets.symmetric(
                      vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.rule_rounded),
                label: const Text(
                  'Competition Rules',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12),
                ),
                onPressed: () => context.push(
                    '/leagues/${widget.leagueId}/rules-editor'),
              ),
            ),
            if (isSwiss) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                        color: AppTheme.limeAccentDark),
                    foregroundColor: AppTheme.limeAccentDark,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.emoji_events),
                  label: Text(
                    l10n.tr(
                        'league_details_generate_knockout_swiss'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12),
                  ),
                  onPressed: () => _generateSwissKnockouts(
                      context, league, teams, fixtures),
                ),
              ),
            ],
            if (isGroup) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                        color: AppTheme.limeAccentDark),
                    foregroundColor: AppTheme.limeAccentDark,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12)),
                  ),
                  icon: const Icon(
                      Icons.emoji_events_outlined),
                  label: Text(
                    l10n.tr(
                        'league_details_generate_knockout_groups'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12),
                  ),
                  onPressed: () => _generateGroupKnockouts(
                      context, league),
                ),
              ),
            ],

            // ── NEW: World Cup knockout generation ───────────────────────────
            if (isWorldCup) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                        color: AppTheme.limeAccentDark),
                    foregroundColor: AppTheme.limeAccentDark,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.public_rounded),
                  label: const Text(
                    'Generate World Cup Knockouts',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12),
                  ),
                  onPressed: () => _generateWorldCupKnockouts(
                      context, league),
                ),
              ),
            ],

            // MODIFIED: Include World Cup in KO viewing/admin row visibility.
            if (isSwiss || isGroup || isWorldCup) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: hasKnockouts
                            ? AppTheme.limeAccentDark
                            : AppTheme
                                .secondaryText(brightness),
                      ),
                      onPressed: hasKnockouts
                          ? () => context.push(
                              '/leagues/${widget.leagueId}/knockout')
                          : showNeedKnockoutsSnack,
                      icon: const Icon(
                          Icons.account_tree_outlined,
                          size: 18),
                      label: Text(
                        l10n.tr(
                            'league_details_view_knockout_bracket'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: hasKnockouts
                            ? AppTheme.limeAccentDark
                            : AppTheme
                                .secondaryText(brightness),
                      ),
                      onPressed: hasKnockouts
                          ? () async {
                              await context.push(
                                  '/leagues/${widget.leagueId}/knockout-admin');
                              if (!mounted) return;
                              _reloadScreen();
                            }
                          : showNeedKnockoutsSnack,
                      icon: const Icon(Icons.sports_score,
                          size: 18),
                      label: Text(
                        l10n.tr(
                            'league_details_manage_ko_scores'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildLeagueSpaceRow(
    BuildContext context,
    League league,
    bool isOwner,
    bool isLive,
    String currentUserId,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    if (!isLive) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.limeAccentDark,
                side: BorderSide(
                  color:
                      AppTheme.limeAccentDark.withOpacity(0.55),
                ),
              ),
              onPressed: () => _onOpenSpace(league),
              icon: const Icon(Icons.spatial_audio_off,
                  size: 18),
              label: const Text(
                'Space',
                style: TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 12),
              ),
            ),
          ),
          if (isOwner) ...[
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.limeAccent,
                  foregroundColor: AppTheme.darkText,
                ),
                onPressed: () =>
                    _onStartSpace(league, currentUserId),
                icon: const Icon(Icons.mic, size: 18),
                label: Text(
                  l10n.tr('league_details_start_space'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      );
    }

    return InkWell(
      onTap: () => _onOpenSpace(league),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.searchBackground(brightness),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color:
                AppTheme.limeAccentDark.withOpacity(0.55),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.graphic_eq,
                color: AppTheme.limeAccentDark, size: 18),
            const SizedBox(width: 8),
            Text(
              l10n.tr('league_details_space_live'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.primaryText(brightness),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            if (isOwner) ...[
              const SizedBox(width: 10),
              Container(
                width: 1,
                height: 16,
                color: AppTheme.cardBorder(brightness),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _onEndSpace(league),
                borderRadius: BorderRadius.circular(999),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.stop_circle_outlined,
                    size: 18,
                    color:
                        Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _upcomingMatchesCard(
    BuildContext context, {
    required List<FixtureMatch> fixtures,
    required Map<String, String> names,
    required Map<String, String> teamImageUrls,
    required List<int> rounds,
    required int selectedRound,
    required void Function(int) onRoundSelected,
  }) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final unplayedFixtures =
        fixtures.where((f) => !f.isPlayed).toList();
    final unplayedRounds = rounds
        .where((r) =>
            unplayedFixtures.any((f) => f.roundNumber == r))
        .toList();

    return Glass(
      padding: const EdgeInsets.all(20),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tr('league_details_coming_up_next'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppTheme.primaryText(brightness),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          if (unplayedRounds.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final r in unplayedRounds) ...[
                    _roundChip(
                      label:
                          '${l10n.tr('league_details_round_prefix')}$r',
                      selected: r == selectedRound,
                      onTap: () => onRoundSelected(r),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (unplayedRounds.isEmpty ||
              unplayedFixtures.isEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  l10n.tr(
                      'league_details_no_upcoming_fixtures'),
                  style: TextStyle(
                    color:
                        AppTheme.secondaryText(brightness),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            Column(
              children: [
                for (final f in unplayedFixtures) ...[
                  _fixtureRow(
                      context, f, names, teamImageUrls),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          Divider(color: AppTheme.cardBorder(brightness)),
          Align(
            alignment: AlignmentDirectional.center,
            child: TextButton(
              onPressed: () async {
                await context.push(
                    '/leagues/${widget.leagueId}/fixtures');
                if (!mounted) return;
                _reloadScreen();
              },
              child: const Text(
                'View all fixtures',
                style: TextStyle(
                  color: AppTheme.limeAccentDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final brightness = Theme.of(context).brightness;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.limeAccent
              : AppTheme.tabInactiveBackground(brightness),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppTheme.limeAccentDark
                : AppTheme.cardBorder(brightness),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? AppTheme.darkText
                : AppTheme.tabInactiveText(brightness),
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _fixtureRow(
    BuildContext context,
    FixtureMatch f,
    Map<String, String> names,
    Map<String, String> teamImageUrls,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final isRtl =
        Directionality.of(context) == TextDirection.rtl;

    final homeName = names[f.homeTeamId] ?? f.homeTeamId;
    final awayName = names[f.awayTeamId] ?? f.awayTeamId;

    final homeUrl =
        (teamImageUrls[f.homeTeamId] ?? '').trim();
    final awayUrl =
        (teamImageUrls[f.awayTeamId] ?? '').trim();

    final chevronIcon =
        isRtl ? Icons.chevron_left : Icons.chevron_right;

    return InkWell(
      onTap: () => context.push(
          '/leagues/${widget.leagueId}/matches/${f.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.searchBackground(brightness),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppTheme.searchOutline(brightness)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color:
                    AppTheme.tabInactiveBackground(brightness),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${l10n.tr('league_details_round_prefix')}${f.roundNumber}',
                style: TextStyle(
                  color: AppTheme.secondaryText(brightness),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      homeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style:
                          theme.textTheme.bodyMedium?.copyWith(
                        color:
                            AppTheme.primaryText(brightness),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TeamThumb(url: homeUrl, size: 20),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14),
              child: Text(
                l10n.tr('league_details_vs'),
                style: const TextStyle(
                  color: AppTheme.limeAccentDark,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  _TeamThumb(url: awayUrl, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      awayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.start,
                      style:
                          theme.textTheme.bodyMedium?.copyWith(
                        color:
                            AppTheme.primaryText(brightness),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              chevronIcon,
              color: AppTheme.secondaryText(brightness),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.searchBackground(brightness),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppTheme.searchOutline(brightness)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.limeAccentDark),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.primaryText(brightness),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: c.withOpacity(0.10),
        border: Border.all(color: c.withOpacity(0.22)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: c,
          fontSize: 11,
        ),
      ),
    );
  }

  Future<void> _generateSwissKnockouts(
    BuildContext context,
    League league,
    List<Team> teams,
    List<FixtureMatch> fixtures,
  ) async {
    final l10n = context.l10n;

    try {
      if (league.format != LeagueFormat.uclSwiss) {
        _toastWarn(
            l10n.tr('league_details_swiss_only_action'));
        return;
      }

      if (!(teams.length == 18 || teams.length == 36)) {
        _toastErr(
            '${l10n.tr('league_details_swiss_team_count_error_prefix')}: ${teams.length}.');
        return;
      }

      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));

      final existing =
          await _repo.getKnockoutMatches(league.id);
      if (existing.isNotEmpty) {
        _toastWarn(l10n.tr(
            'league_details_knockout_already_generated'));
        return;
      }

      final swissMatches = fixtures
          .where((m) => m.groupId == null)
          .toList();
      if (swissMatches.isEmpty) {
        _toastErr(
            l10n.tr('league_details_swiss_no_matches_found'));
        return;
      }

      final requiredRounds = league.settings.swissRounds;

      final roundsSet =
          swissMatches.map((m) => m.roundNumber).toSet();
      final hasAllRounds =
          List.generate(requiredRounds, (i) => i + 1)
              .every((r) => roundsSet.contains(r));
      if (!hasAllRounds) {
        _toastWarn(
          '${l10n.tr('league_details_generate_all_swiss_rounds_prefix')} $requiredRounds ${l10n.tr('league_details_generate_all_swiss_rounds_suffix')}',
        );
        return;
      }

      final anyUnplayedInRequired = swissMatches
          .where((m) => m.roundNumber <= requiredRounds)
          .any((m) => !m.isPlayed);
      if (anyUnplayedInRequired) {
        _toastWarn(
          '${l10n.tr('league_details_finish_all_swiss_rounds_prefix')} $requiredRounds ${l10n.tr('league_details_finish_all_swiss_rounds_suffix')}',
        );
        return;
      }

      final swissStandings = StandingsCalculator.calculate(
          teams: teams, matches: swissMatches);

      if (swissStandings.length != teams.length) {
        _toastErr(l10n.tr(
            'league_details_standings_team_mismatch'));
        return;
      }

      final koMatches =
          TournamentController.seedSwissKnockouts(
        leagueId: league.id,
        swissStandings: swissStandings,
      );

      if (koMatches.isEmpty) {
        _toastErr(l10n.tr(
            'league_details_failed_seed_swiss_knockout'));
        return;
      }

      await _repo.saveKnockoutMatches(
          league.id, koMatches);

      final label = (teams.length == 36)
          ? l10n.tr(
              'league_details_swiss_knockout_generated_36')
          : l10n.tr(
              'league_details_swiss_knockout_generated_18');

      _toastOk(label);
      if (mounted) _reloadScreen();
    } catch (e) {
      _toastErr(
        UserFriendlyError.toMessage(
            e is Object ? e : Exception('unknown')),
      );
    }
  }

  Future<void> _generateGroupKnockouts(
    BuildContext context,
    League league,
  ) async {
    final l10n = context.l10n;

    try {
      if (league.format != LeagueFormat.uclGroup) {
        _toastWarn(
            l10n.tr('league_details_groups_only_action'));
        return;
      }

      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));

      final existing =
          await _repo.getKnockoutMatches(league.id);
      if (existing.isNotEmpty) {
        _toastWarn(l10n.tr(
            'league_details_knockout_already_generated'));
        return;
      }

      final teams = await _repo.getTeams(league.id);
      final matches = await _repo.getMatches(league.id);

      if (!(teams.length == 16 || teams.length == 32)) {
        _toastErr(
            '${l10n.tr('league_details_group_team_count_error_prefix')}: ${teams.length}.');
        return;
      }

      if (league.settings.groupSize != 4) {
        _toastWarn(
            '${l10n.tr('league_details_group_size_expected_4_prefix')}: ${league.settings.groupSize}.');
      }

      final groupMatches =
          matches.where((m) => m.groupId != null).toList();
      if (groupMatches.isEmpty) {
        _toastErr(l10n
            .tr('league_details_no_group_matches_found'));
        return;
      }

      final anyUnplayedGroup =
          groupMatches.any((m) => !m.isPlayed);
      if (anyUnplayedGroup) {
        _toastWarn(l10n.tr(
            'league_details_finish_all_group_matches_first'));
        return;
      }

      final groupIds = groupMatches
          .map((m) => m.groupId)
          .whereType<String>()
          .map((g) => g.trim())
          .where((g) => g.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      final expectedGroupCount = teams.length ~/ 4;
      if (groupIds.length != expectedGroupCount) {
        _toastErr(
          '${l10n.tr('league_details_invalid_group_structure_prefix')} $expectedGroupCount ${l10n.tr('league_details_invalid_group_structure_mid')} ${teams.length} ${l10n.tr('league_details_invalid_group_structure_suffix')} ${groupIds.length}.',
        );
        return;
      }

      final groupStandings =
          <String, List<StandingsRow>>{};

      for (final groupId in groupIds) {
        final gm = groupMatches
            .where((m) => m.groupId == groupId)
            .toList();
        if (gm.isEmpty) continue;

        final teamIds = <String>{};
        for (final m in gm) {
          teamIds.add(m.homeTeamId);
          teamIds.add(m.awayTeamId);
        }

        final groupTeams = teams
            .where((t) => teamIds.contains(t.id))
            .toList();
        if (groupTeams.length != 4) {
          _toastErr(
              '${l10n.tr('league_details_group_not_four_prefix')} $groupId ${l10n.tr('league_details_group_not_four_suffix')} ${groupTeams.length}.');
          return;
        }

        final rows = StandingsCalculator.calculate(
            teams: groupTeams, matches: gm);
        if (rows.length != 4) {
          _toastErr(
              '${l10n.tr('league_details_group_standings_invalid_prefix')} $groupId.');
          return;
        }
        groupStandings[groupId] = rows;
      }

      if (groupStandings.length != expectedGroupCount) {
        _toastErr(
            '${l10n.tr('league_details_group_standings_incomplete_prefix')} $expectedGroupCount.');
        return;
      }

      final koMatches =
          TournamentController.seedKnockoutsFromGroups(
        leagueId: league.id,
        groupStandings: groupStandings,
      );

      if (koMatches.isEmpty) {
        _toastErr(l10n
            .tr('league_details_failed_seed_group_knockout'));
        return;
      }

      await _repo.saveKnockoutMatches(
          league.id, koMatches);

      final label = (teams.length == 32)
          ? l10n.tr(
              'league_details_group_knockout_generated_32')
          : l10n.tr(
              'league_details_group_knockout_generated_16');

      _toastOk(label);
      if (mounted) _reloadScreen();
    } catch (e) {
      _toastErr(
        UserFriendlyError.toMessage(
            e is Object ? e : Exception('unknown')),
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // NEW: World Cup knockouts generation (FIFA 2022 / FIFA 2026)
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _generateWorldCupKnockouts(
    BuildContext context,
    League league,
  ) async {
    try {
      if (league.format != LeagueFormat.worldCup) {
        _toastWarn('This action is only available for World Cup competitions.');
        return;
      }

      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 4));

      final existing =
          await _repo.getKnockoutMatches(league.id);
      if (existing.isNotEmpty) {
        _toastWarn(context.l10n.tr('league_details_knockout_already_generated'));
        if (mounted) setState(() => _reloadScreen);
        return;
      }

      final teams = await _repo.getTeams(league.id);
      final matches = await _repo.getMatches(league.id);

      final wcFormat = league.worldCupFormat;

      // Validate team count matches selected format (32/48).
      if (teams.length != wcFormat.teamCount) {
        _toastErr('Invalid team count for ${wcFormat.displayName}: ${teams.length}.');
        return;
      }

      // World Cup group stage matches are the ones with groupId != null.
      final groupMatches =
          matches.where((m) => m.groupId != null).toList();
      if (groupMatches.isEmpty) {
        _toastErr('No World Cup group stage matches found yet.');
        return;
      }

      // Require all group stage matches completed before seeding knockouts.
      final anyUnplayedGroup =
          groupMatches.any((m) => !m.isPlayed);
      if (anyUnplayedGroup) {
        _toastWarn('Finish all group stage matches first before generating knockouts.');
        return;
      }

      final groupIds = groupMatches
          .map((m) => m.groupId)
          .whereType<String>()
          .map((g) => g.trim())
          .where((g) => g.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      // Validate expected number of groups (8 for 32-team, 12 for 48-team).
      final expectedGroupCount = wcFormat.groupCount;
      if (groupIds.length != expectedGroupCount) {
        _toastErr('Invalid group structure: expected $expectedGroupCount groups, found ${groupIds.length}.');
        return;
      }

      final groupStandings = <String, List<StandingsRow>>{};

      // Build standings for each group using FIFA-compliant tie-breakers.
      for (final groupId in groupIds) {
        final gm = groupMatches
            .where((m) => m.groupId == groupId)
            .toList();
        if (gm.isEmpty) continue;

        final teamIds = <String>{};
        for (final m in gm) {
          teamIds.add(m.homeTeamId);
          teamIds.add(m.awayTeamId);
        }

        final groupTeams = teams
            .where((t) => teamIds.contains(t.id))
            .toList();
        if (groupTeams.length != 4) {
          _toastErr('Invalid group ($groupId): expected 4 teams, found ${groupTeams.length}.');
          return;
        }

        final rows = StandingsCalculator.calculate(
          teams: groupTeams,
          matches: gm,
          fifaGroupTieBreakers: true, // Enable FIFA H2H for World Cup
        );
        if (rows.length != 4) {
          _toastErr('Invalid standings output for group $groupId.');
          return;
        }
        groupStandings[groupId] = rows;
      }

      if (groupStandings.length != expectedGroupCount) {
        _toastErr('Incomplete group standings: expected $expectedGroupCount groups.');
        return;
      }

      // Seed KO bracket based on format.
      final List<KnockoutMatch> koMatches = (wcFormat == WorldCupFormat.fifa2026)
          ? TournamentController.seedWorldCupKnockouts48(
              leagueId: league.id,
              groupStandings: groupStandings,
            )
          : TournamentController.seedWorldCupKnockouts32(
              leagueId: league.id,
              groupStandings: groupStandings,
            );

      if (koMatches.isEmpty) {
        _toastErr('Failed to seed World Cup knockout bracket.');
        return;
      }

      await _repo.saveKnockoutMatches(league.id, koMatches);

      _toastOk(
        wcFormat == WorldCupFormat.fifa2026
            ? 'World Cup knockouts generated (Round of 32).'
            : 'World Cup knockouts generated (Round of 16).',
      );

      if (mounted) _reloadScreen();
    } catch (e) {
      _toastErr(
        UserFriendlyError.toMessage(
            e is Object ? e : Exception('unknown')),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private widgets (unchanged logic, same as original)
// ─────────────────────────────────────────────────────────────────────────────

class _LeagueHero extends StatelessWidget {
  const _LeagueHero({
    required this.leagueImageUrl,
    required this.sponsorImageUrl,
  });

  final String leagueImageUrl;
  final String sponsorImageUrl;

  bool _looksLikeHttpUrl(String s) {
    final u = s.trim().toLowerCase();
    return u.startsWith('https://') || u.startsWith('http://');
  }

  String _cloudinaryOptimizedUrl(
    String url, {
    int width = 1200,
    int height = 600,
    String crop = 'fill',
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

    final transforms = <String>[
      'f_auto',
      'q_auto',
      if (width > 0) 'w_$width',
      if (height > 0) 'h_$height',
      (crop == 'fit') ? 'c_fit' : 'c_fill',
      if (crop != 'fit') 'g_auto',
    ].join(',');

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

  Uint8List? _tryDecodeDataUri(String raw) {
    final s = raw.trim();
    if (!s.startsWith('data:image')) return null;
    final idx = s.indexOf('base64,');
    if (idx < 0) return null;
    final b64 = s.substring(idx + 'base64,'.length);
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Widget _imageOrPlaceholder(
    BuildContext context,
    String url, {
    BoxFit fit = BoxFit.cover,
    int cacheWidth = 1200,
    int cacheHeight = 600,
    bool optimizeCloudinary = true,
  }) {
    final brightness = Theme.of(context).brightness;

    final u = url.trim();
    final bytes = u.isEmpty ? null : _tryDecodeDataUri(u);

    if (bytes != null) {
      return Image.memory(bytes,
          fit: fit, gaplessPlayback: true);
    }

    if (u.isNotEmpty && _looksLikeHttpUrl(u)) {
      final deliver = optimizeCloudinary
          ? _cloudinaryOptimizedUrl(u,
              width: cacheWidth, height: cacheHeight)
          : u;

      return Image.network(
        deliver,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(
            Icons.emoji_events_outlined,
            size: 36,
            color: AppTheme.secondaryText(brightness),
          ),
        ),
        loadingBuilder: (context, child, event) {
          if (event == null) return child;
          return Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.limeAccentDark
                    .withOpacity(0.85),
              ),
            ),
          );
        },
      );
    }

    if (u.isNotEmpty) {
      return Image.network(
        u,
        fit: fit,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(
            Icons.emoji_events_outlined,
            size: 36,
            color: AppTheme.secondaryText(brightness),
          ),
        ),
        loadingBuilder: (context, child, event) {
          if (event == null) return child;
          return Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.limeAccentDark
                    .withOpacity(0.85),
              ),
            ),
          );
        },
      );
    }

    return Center(
      child: Icon(
        Icons.emoji_events_outlined,
        size: 48,
        color: AppTheme.secondaryText(brightness),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    final mainUrl = leagueImageUrl.trim();
    final sponsorUrl = sponsorImageUrl.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.searchBackground(brightness),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppTheme.searchOutline(brightness)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _imageOrPlaceholder(
              context,
              mainUrl,
              fit: BoxFit.cover,
              cacheWidth: 1200,
              cacheHeight: 600,
              optimizeCloudinary: true,
            ),
            if (sponsorUrl.isNotEmpty)
              PositionedDirectional(
                end: 10,
                bottom: 10,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.92),
                      borderRadius:
                          BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            AppTheme.cardBorder(brightness),
                      ),
                    ),
                    child: _imageOrPlaceholder(
                      context,
                      sponsorUrl,
                      fit: BoxFit.contain,
                      cacheWidth: 160,
                      cacheHeight: 160,
                      optimizeCloudinary: true,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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
    return u.startsWith('https://') ||
        u.startsWith('http://');
  }

  String _cloudinaryOptimizedUrl(String url,
      {int width = 64, int height = 64}) {
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
    final brightness = Theme.of(context).brightness;

    final raw = url.trim();
    final has = raw.isNotEmpty && _looksLikeHttpUrl(raw);

    final px = (size * 3).clamp(48, 96).toInt();
    final d = has
        ? _cloudinaryOptimizedUrl(raw,
            width: px, height: px)
        : '';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.searchBackground(brightness),
        shape: BoxShape.circle,
        border: Border.all(
            color: AppTheme.searchOutline(brightness)),
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
                  size: size * 0.70,
                  color: AppTheme.secondaryText(brightness),
                ),
                loadingBuilder: (context, child, event) {
                  if (event == null) return child;
                  return Icon(
                    Icons.emoji_events_outlined,
                    size: size * 0.70,
                    color:
                        AppTheme.secondaryText(brightness),
                  );
                },
              )
            : Icon(
                Icons.emoji_events_outlined,
                size: size * 0.70,
                color: AppTheme.secondaryText(brightness),
              ),
      ),
    );
  }
}