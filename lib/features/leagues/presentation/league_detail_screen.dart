import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/sync_trigger.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../social/ui/widgets/glass_announcement.dart';
import '../data/league_announcements_local.dart';
import '../data/league_spaces_local.dart';
import '../data/leagues_repository_local.dart';
import '../domain/logic/tournament_controller.dart';
import '../domain/standings/standings.dart';
import '../domain/standings/standings_calculator.dart';
import '../models/fixture_match.dart';
import '../models/knockout_match.dart';
import '../models/league.dart';
import '../models/league_announcement.dart';
import '../models/league_format.dart';
import '../models/league_space.dart';
import '../models/membership.dart';
import '../models/team.dart';

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
  late final LeagueAnnouncementsFirebase _annRepo;
  late final LeagueSpacesFirebase _spaceRepo;

  int? _lastViewedRound;
  static String _lastRoundKey(String leagueId) => 'ui_last_round_$leagueId';

  int _lastSeenAnnMs = 0;
  static String _lastSeenAnnKey(String leagueId) => 'ui_last_seen_ann_$leagueId';

  final ScrollController _annScrollController = ScrollController();
  Timer? _annScrollTimer;
  int _annLastCount = 0;

  @override
  void initState() {
    super.initState();
    _prefs = ref.read(prefsServiceProvider);
    _repo = LocalLeaguesRepository(_prefs);
    _annRepo = LeagueAnnouncementsFirebase(_prefs);
    _spaceRepo = LeagueSpacesFirebase(_prefs);

    final rawRound = _prefs.getString(_lastRoundKey(widget.leagueId));
    _lastViewedRound = int.tryParse((rawRound ?? '').trim());

    _lastSeenAnnMs = _prefs.getInt(_lastSeenAnnKey(widget.leagueId)) ?? 0;

    // ignore: discarded_futures
    SyncTrigger.trySync().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _annScrollTimer?.cancel();
    _annScrollController.dispose();
    super.dispose();
  }

  void _toast(
    String msg, {
    Color bg = const Color(0xFF101522),
    Color fg = Colors.white,
    IconData? icon,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg,
        margin: const EdgeInsets.all(12),
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                msg,
                style: TextStyle(color: fg, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _toastOk(String msg) => _toast(
        msg,
        bg: Colors.cyanAccent.withOpacity(0.18),
        fg: Colors.cyanAccent,
        icon: Icons.check_circle_outline,
      );

  void _toastWarn(String msg) => _toast(
        msg,
        bg: Colors.orangeAccent.withOpacity(0.14),
        fg: Colors.orangeAccent,
        icon: Icons.warning_amber_rounded,
      );

  void _toastErr(String msg) => _toast(
        msg,
        bg: Colors.redAccent.withOpacity(0.14),
        fg: Colors.redAccent,
        icon: Icons.error_outline,
      );

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

    _annScrollTimer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
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

  Future<Map<String, dynamic>> _loadData() async {
    final league = await _repo.getLeagueById(widget.leagueId);
    if (league == null) {
      throw const _L10nException('leagues_error_not_found_local_storage');
    }

    final fixtures = await _repo.getMatches(widget.leagueId);
    final teams = await _repo.getTeams(widget.leagueId);
    final knockouts = await _repo.getKnockoutMatches(widget.leagueId);
    final announcements = await _annRepo.listForLeague(widget.leagueId);

    final currentUserId = _prefs.getCurrentUserId() ?? '';

    final membership = await _repo.getMembership(
      leagueId: widget.leagueId,
      userId: currentUserId,
    );

    final teamNames = {for (final t in teams) t.id: t.name};

    final space = await _spaceRepo.getActiveSpace(widget.leagueId);

    return {
      'league': league,
      'fixtures': fixtures,
      'teams': teams,
      'teamNames': teamNames,
      'currentUserId': currentUserId,
      'membership': membership,
      'knockouts': knockouts,
      'announcements': announcements,
      'space': space,
    };
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
    final rounds = sorted.map((m) => m.roundNumber).toSet().toList()..sort();
    return rounds;
  }

  List<FixtureMatch> _computeUpcomingUnplayed({
    required List<FixtureMatch> sortedAll,
    required int selectedRound,
    int limit = 8,
  }) {
    final unplayed = sortedAll.where((m) => !m.isPlayed).toList();
    if (unplayed.isEmpty) return [];

    final roundsWithUnplayed = unplayed.map((m) => m.roundNumber).toSet().toList()..sort();

    int effectiveRound = selectedRound;
    if (!roundsWithUnplayed.contains(effectiveRound)) {
      final next = roundsWithUnplayed.where((r) => r > selectedRound).toList();
      effectiveRound = next.isNotEmpty ? next.first : roundsWithUnplayed.first;
    }

    if (effectiveRound != selectedRound) {
      _persistRound(effectiveRound);
    }

    final filtered = sortedAll.where((m) => !m.isPlayed && m.roundNumber >= effectiveRound).toList();
    if (filtered.length <= limit) return filtered;
    return filtered.take(limit).toList();
  }

  Future<void> _onStartSpace(League league, String currentUserId) async {
    try {
      await _spaceRepo.startSpace(
        leagueId: league.id,
        hostUserId: currentUserId,
        title: '${league.name} ${context.l10n.tr('league_details_space_title_suffix')}',
      );

      await SyncTrigger.trySync();

      if (!mounted) return;
      setState(() {});
      _toastOk(context.l10n.tr('league_details_space_started'));
    } catch (e) {
      _toastErr('${context.l10n.tr('league_details_failed_to_start_space')}: $e');
    }
  }

  Future<void> _onEndSpace(League league) async {
    try {
      await _spaceRepo.endSpace(league.id);

      await SyncTrigger.trySync();

      if (!mounted) return;
      setState(() {});
      _toastOk(context.l10n.tr('league_details_space_ended'));
    } catch (e) {
      _toastErr('${context.l10n.tr('league_details_failed_to_end_space')}: $e');
    }
  }

  void _onOpenSpace(League league) {
    context.push('/leagues/${league.id}/space');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final primary = Theme.of(context).colorScheme.primary;
    final isWide = MediaQuery.of(context).size.width > 600;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('league_details_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: l10n.tr('league_details_sync_tooltip'),
            onPressed: () async {
              await SyncTrigger.trySync();
              if (mounted) setState(() {});
              _toastOk(l10n.tr('league_details_synced_toast'));
            },
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _loadData(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.cyanAccent),
                );
              }

              if (snapshot.hasError) {
                final err = snapshot.error;
                final message = (err is _L10nException) ? l10n.tr(err.key) : '$err';

                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          '${l10n.tr('common_error_prefix')}: $message',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        if (kDebugMode && err != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            err.runtimeType.toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => setState(() {}),
                          child: Text(
                            l10n.tr('common_retry'),
                            style: const TextStyle(color: Colors.cyanAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (!snapshot.hasData) return const SizedBox.shrink();

              final league = snapshot.data!['league'] as League;
              final fixtures = snapshot.data!['fixtures'] as List<FixtureMatch>;
              final teams = snapshot.data!['teams'] as List<Team>;
              final teamNames = snapshot.data!['teamNames'] as Map<String, String>;
              final currentUserId = snapshot.data!['currentUserId'] as String;
              final membership = snapshot.data!['membership'] as Membership?;
              final knockouts = snapshot.data!['knockouts'] as List<KnockoutMatch>;
              final announcements = snapshot.data!['announcements'] as List<LeagueAnnouncement>;
              final space = snapshot.data!['space'] as LeagueSpace?;

              final sorted = _sortedSchedule(fixtures);
              final rounds = _allRounds(sorted);
              final selectedRound = (_lastViewedRound != null && rounds.contains(_lastViewedRound))
                  ? _lastViewedRound!
                  : (rounds.isEmpty ? 1 : rounds.first);

              final upcoming = _computeUpcomingUnplayed(
                sortedAll: sorted,
                selectedRound: selectedRound,
                limit: 8,
              );

              int latestAnnMs = 0;
              if (announcements.isNotEmpty) {
                latestAnnMs = announcements.map((a) => a.createdAtMs).reduce(max);
              }
              final hasUnreadAnnouncements = announcements.isNotEmpty && latestAnnMs > _lastSeenAnnMs;

              if (hasUnreadAnnouncements) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _markAnnouncementsSeen(latestAnnMs);
                });
              }

              _ensureAnnounceAutoScroll(announcements.length);

              final isOwnerByLeague = membership?.role == LeagueRole.organizer;
              final isOwnerFallback = league.organizerUserId == currentUserId;
              final isOwner = isOwnerByLeague || isOwnerFallback;

              return ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 600 : 500),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  children: [
                    _overviewCard(context, primary, league, isOwner),
                    if (announcements.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _announcementsCard(context, announcements, hasUnreadAnnouncements),
                    ],
                    const SizedBox(height: 16),
                    _quickActions(
                      context,
                      league,
                      isOwner,
                      fixtures,
                      teams,
                      knockouts,
                      space,
                      currentUserId,
                    ),
                    const SizedBox(height: 16),
                    _upcomingMatchesCard(
                      context,
                      fixtures: upcoming,
                      names: teamNames,
                      rounds: rounds,
                      selectedRound: selectedRound,
                      onRoundSelected: (r) => _persistRound(r),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _overviewCard(BuildContext context, Color c, League league, bool isOwner) {
    final l10n = context.l10n;
    final settings = league.settings;

    final rulePills = <Widget>[
      _pill(league.isPrivate ? l10n.tr('league_details_private') : l10n.tr('league_details_public'), Colors.cyanAccent),
      _pill('${league.maxTeams} ${l10n.tr('league_details_teams_max_suffix')}', Colors.orangeAccent),
      _pill(league.region, Colors.purpleAccent),
      _pill(settings.doubleRoundRobin ? l10n.tr('league_details_double_rr') : l10n.tr('league_details_single_rr'), Colors.lightBlueAccent),
    ];

    if (league.format == LeagueFormat.uclGroup) {
      rulePills.add(_pill('${l10n.tr('league_details_group_size_prefix')} ${settings.groupSize}', Colors.tealAccent));
    }
    if (league.format == LeagueFormat.uclSwiss) {
      rulePills.add(_pill('${l10n.tr('league_details_swiss_rounds_prefix')} ${settings.swissRounds}', Colors.tealAccent));
    }

    return Glass(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  league.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              if (isOwner)
                Tooltip(
                  message: l10n.tr('league_details_organiser_tooltip'),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.verified_user, color: Colors.cyanAccent, size: 20),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${league.format.displayName} • ${league.season}',
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
          const SizedBox(height: 18),
          Wrap(spacing: 8, runSpacing: 8, children: rulePills),
        ],
      ),
    );
  }

  Widget _announcementsCard(BuildContext context, List<LeagueAnnouncement> anns, bool hasUnread) {
    final l10n = context.l10n;

    final sorted = anns.toList()..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    final formatter = DateFormat('MMM d • HH:mm');

    return Glass(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.tr('league_details_announcements_title'),
                style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16),
              ),
              if (hasUnread) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    l10n.tr('league_details_new_badge'),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final a = sorted[index];
                final timeStr = formatter.format(DateTime.fromMillisecondsSinceEpoch(a.createdAtMs));
                return GlassAnnouncement(title: a.title, message: a.message, time: timeStr);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActions(
    BuildContext context,
    League league,
    bool isOwner,
    List<FixtureMatch> fixtures,
    List<Team> teams,
    List<KnockoutMatch> knockouts,
    LeagueSpace? space,
    String currentUserId,
  ) {
    final l10n = context.l10n;

    final isSwiss = league.format == LeagueFormat.uclSwiss;
    final isGroup = league.format == LeagueFormat.uclGroup;
    final hasKnockouts = knockouts.isNotEmpty;
    final spaceLive = space?.isLive == true;

    void showNeedKnockoutsSnack() => _toastWarn(l10n.tr('league_details_need_knockouts_first'));

    return Glass(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tr('league_details_menu_title'),
            style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 8),
          _buildLeagueSpaceRow(context, league, isOwner, spaceLive, currentUserId),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.list_alt,
                  label: l10n.tr('league_details_fixtures'),
                  onTap: () => context.push('/leagues/${widget.leagueId}/fixtures'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  icon: Icons.leaderboard,
                  label: l10n.tr('league_details_standings'),
                  onTap: () => context.push('/leagues/${widget.leagueId}/standings'),
                ),
              ),
            ],
          ),
          if (isOwner) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.edit_note),
                label: Text(
                  l10n.tr('league_details_manage_league_scores'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  await context.push('/leagues/${widget.leagueId}/admin-scores');
                  if (!mounted) return;
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  foregroundColor: Colors.cyanAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.settings),
                label: Text(
                  l10n.tr('league_details_league_settings_admin'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                onPressed: () => context.push('/leagues/${widget.leagueId}/admin'),
              ),
            ),
            if (isSwiss) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.cyanAccent),
                    foregroundColor: Colors.cyanAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.emoji_events),
                  label: Text(
                    l10n.tr('league_details_generate_knockout_swiss'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: () => _generateSwissKnockouts(context, league, teams, fixtures),
                ),
              ),
            ],
            if (isGroup) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.cyanAccent),
                    foregroundColor: Colors.cyanAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: Text(
                    l10n.tr('league_details_generate_knockout_groups'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: () => _generateGroupKnockouts(context, league),
                ),
              ),
            ],
            if (isSwiss || isGroup) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: hasKnockouts ? Colors.cyanAccent : Colors.white30,
                      ),
                      onPressed: hasKnockouts ? () => context.push('/leagues/${widget.leagueId}/knockout') : showNeedKnockoutsSnack,
                      icon: const Icon(Icons.account_tree_outlined, size: 18),
                      label: Text(
                        l10n.tr('league_details_view_knockout_bracket'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: hasKnockouts ? Colors.cyanAccent : Colors.white30,
                      ),
                      onPressed: hasKnockouts
                          ? () async {
                              await context.push('/leagues/${widget.leagueId}/knockout-admin');
                              if (!mounted) return;
                              setState(() {});
                            }
                          : showNeedKnockoutsSnack,
                      icon: const Icon(Icons.sports_score, size: 18),
                      label: Text(
                        l10n.tr('league_details_manage_ko_scores'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ] else ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Text(
                l10n.tr('league_details_view_only_banner'),
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
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

    if (!isLive && !isOwner) return const SizedBox.shrink();

    if (!isLive && isOwner) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.cyanAccent),
          onPressed: () => _onStartSpace(league, currentUserId),
          icon: const Icon(Icons.mic, size: 18),
          label: Text(
            l10n.tr('league_details_start_space'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => _onOpenSpace(league),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.cyanAccent.withOpacity(0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.graphic_eq, color: Colors.cyanAccent, size: 18),
            const SizedBox(width: 8),
            Text(
              l10n.tr('league_details_space_live'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
            ),
            if (isOwner) ...[
              const SizedBox(width: 10),
              Container(width: 1, height: 16, color: Colors.white24),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _onEndSpace(league),
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.stop_circle_outlined, size: 18, color: Colors.redAccent),
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
    required List<int> rounds,
    required int selectedRound,
    required void Function(int) onRoundSelected,
  }) {
    final l10n = context.l10n;

    final unplayedFixtures = fixtures.where((f) => !f.isPlayed).toList();
    final unplayedRounds = rounds.where((r) => unplayedFixtures.any((f) => f.roundNumber == r)).toList();

    return Glass(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tr('league_details_coming_up_next'),
            style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (unplayedRounds.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final r in unplayedRounds) ...[
                    _roundChip(
                      label: '${l10n.tr('league_details_round_prefix')}$r',
                      selected: r == selectedRound,
                      onTap: () => onRoundSelected(r),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (unplayedRounds.isEmpty || unplayedFixtures.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  l10n.tr('league_details_no_upcoming_fixtures'),
                  style: const TextStyle(color: Colors.white38),
                ),
              ),
            )
          else
            Column(
              children: [
                for (final f in unplayedFixtures) ...[
                  _fixtureRow(context, f, names),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          const Divider(color: Colors.white10),
          Align(
            alignment: AlignmentDirectional.center,
            child: TextButton(
              onPressed: () => context.push('/leagues/${widget.leagueId}/fixtures'),
              child: Text(
                l10n.tr('league_details_view_all_fixtures'),
                style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundChip({required String label, required bool selected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.cyanAccent : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? Colors.cyanAccent : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _fixtureRow(BuildContext context, FixtureMatch f, Map<String, String> names) {
    final l10n = context.l10n;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final homeName = names[f.homeTeamId] ?? f.homeTeamId;
    final awayName = names[f.awayTeamId] ?? f.awayTeamId;

    final chevronIcon = isRtl ? Icons.chevron_left : Icons.chevron_right;

    return InkWell(
      onTap: () => context.push('/leagues/${widget.leagueId}/matches/${f.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
              child: Text(
                '${l10n.tr('league_details_round_prefix')}${f.roundNumber}',
                style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                homeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                l10n.tr('league_details_vs'),
                style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w900, fontSize: 12),
              ),
            ),
            Expanded(
              child: Text(
                awayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            Icon(chevronIcon, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white70),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: c.withOpacity(0.1),
        border: Border.all(color: c.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(fontWeight: FontWeight.bold, color: c, fontSize: 11),
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

    if (league.format != LeagueFormat.uclSwiss) {
      _toastWarn(l10n.tr('league_details_swiss_only_action'));
      return;
    }

    if (!(teams.length == 18 || teams.length == 36)) {
      _toastErr('${l10n.tr('league_details_swiss_team_count_error_prefix')}: ${teams.length}.');
      return;
    }

    final existing = await _repo.getKnockoutMatches(league.id);
    if (existing.isNotEmpty) {
      _toastWarn(l10n.tr('league_details_knockout_already_generated'));
      return;
    }

    final swissMatches = fixtures.where((m) => m.groupId == null).toList();
    if (swissMatches.isEmpty) {
      _toastErr(l10n.tr('league_details_swiss_no_matches_found'));
      return;
    }

    final requiredRounds = league.settings.swissRounds;

    final roundsSet = swissMatches.map((m) => m.roundNumber).toSet();
    final hasAllRounds = List.generate(requiredRounds, (i) => i + 1).every((r) => roundsSet.contains(r));
    if (!hasAllRounds) {
      _toastWarn('${l10n.tr('league_details_generate_all_swiss_rounds_prefix')} $requiredRounds ${l10n.tr('league_details_generate_all_swiss_rounds_suffix')}');
      return;
    }

    final anyUnplayedInRequired = swissMatches.where((m) => m.roundNumber <= requiredRounds).any((m) => !m.isPlayed);
    if (anyUnplayedInRequired) {
      _toastWarn('${l10n.tr('league_details_finish_all_swiss_rounds_prefix')} $requiredRounds ${l10n.tr('league_details_finish_all_swiss_rounds_suffix')}');
      return;
    }

    final swissStandings = StandingsCalculator.calculate(teams: teams, matches: swissMatches);

    if (swissStandings.length != teams.length) {
      _toastErr(l10n.tr('league_details_standings_team_mismatch'));
      return;
    }

    final koMatches = TournamentController.seedSwissKnockouts(
      leagueId: league.id,
      swissStandings: swissStandings,
    );

    if (koMatches.isEmpty) {
      _toastErr(l10n.tr('league_details_failed_seed_swiss_knockout'));
      return;
    }

    await _repo.saveKnockoutMatches(league.id, koMatches);
    await SyncTrigger.trySync();

    final label = (teams.length == 36)
        ? l10n.tr('league_details_swiss_knockout_generated_36')
        : l10n.tr('league_details_swiss_knockout_generated_18');

    _toastOk(label);
    if (mounted) setState(() {});
  }

  Future<void> _generateGroupKnockouts(BuildContext context, League league) async {
    final l10n = context.l10n;

    if (league.format != LeagueFormat.uclGroup) {
      _toastWarn(l10n.tr('league_details_groups_only_action'));
      return;
    }

    final existing = await _repo.getKnockoutMatches(league.id);
    if (existing.isNotEmpty) {
      _toastWarn(l10n.tr('league_details_knockout_already_generated'));
      return;
    }

    final teams = await _repo.getTeams(league.id);
    final matches = await _repo.getMatches(league.id);

    if (!(teams.length == 16 || teams.length == 32)) {
      _toastErr('${l10n.tr('league_details_group_team_count_error_prefix')}: ${teams.length}.');
      return;
    }

    if (league.settings.groupSize != 4) {
      _toastWarn('${l10n.tr('league_details_group_size_expected_4_prefix')}: ${league.settings.groupSize}.');
    }

    final groupMatches = matches.where((m) => m.groupId != null).toList();
    if (groupMatches.isEmpty) {
      _toastErr(l10n.tr('league_details_no_group_matches_found'));
      return;
    }

    final anyUnplayedGroup = groupMatches.any((m) => !m.isPlayed);
    if (anyUnplayedGroup) {
      _toastWarn(l10n.tr('league_details_finish_all_group_matches_first'));
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
      _toastErr('${l10n.tr('league_details_invalid_group_structure_prefix')} $expectedGroupCount ${l10n.tr('league_details_invalid_group_structure_mid')} ${teams.length} ${l10n.tr('league_details_invalid_group_structure_suffix')} ${groupIds.length}.');
      return;
    }

    final groupStandings = <String, List<StandingsRow>>{};

    for (final groupId in groupIds) {
      final gm = groupMatches.where((m) => m.groupId == groupId).toList();
      if (gm.isEmpty) continue;

      final teamIds = <String>{};
      for (final m in gm) {
        teamIds.add(m.homeTeamId);
        teamIds.add(m.awayTeamId);
      }

      final groupTeams = teams.where((t) => teamIds.contains(t.id)).toList();
      if (groupTeams.length != 4) {
        _toastErr('${l10n.tr('league_details_group_not_four_prefix')} $groupId ${l10n.tr('league_details_group_not_four_suffix')} ${groupTeams.length}.');
        return;
      }

      final rows = StandingsCalculator.calculate(teams: groupTeams, matches: gm);
      if (rows.length != 4) {
        _toastErr('${l10n.tr('league_details_group_standings_invalid_prefix')} $groupId.');
        return;
      }
      groupStandings[groupId] = rows;
    }

    if (groupStandings.length != expectedGroupCount) {
      _toastErr('${l10n.tr('league_details_group_standings_incomplete_prefix')} $expectedGroupCount.');
      return;
    }

    final koMatches = TournamentController.seedKnockoutsFromGroups(
      leagueId: league.id,
      groupStandings: groupStandings,
    );

    if (koMatches.isEmpty) {
      _toastErr(l10n.tr('league_details_failed_seed_group_knockout'));
      return;
    }

    await _repo.saveKnockoutMatches(league.id, koMatches);
    await SyncTrigger.trySync();

    final label = (teams.length == 32)
        ? l10n.tr('league_details_group_knockout_generated_32')
        : l10n.tr('league_details_group_knockout_generated_16');

    _toastOk(label);
    if (mounted) setState(() {});
  }
}
