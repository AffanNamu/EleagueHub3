import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../social/ui/widgets/glass_announcement.dart';
import '../data/leagues_repository_local.dart';
import '../data/league_announcements_local.dart';
import '../domain/logic/tournament_controller.dart';
import '../domain/standings/standings.dart';
import '../domain/standings/standings_calculator.dart';
import '../models/fixture_match.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../models/membership.dart';
import '../models/team.dart';
import '../models/knockout_match.dart';
import '../models/league_announcement.dart';

class LeagueDetailScreen extends ConsumerStatefulWidget {
  final String leagueId;

  const LeagueDetailScreen({
    super.key,
    required this.leagueId,
  });

  @override
  ConsumerState<LeagueDetailScreen> createState() =>
      _LeagueDetailScreenState();
}

class _LeagueDetailScreenState
    extends ConsumerState<LeagueDetailScreen> {
  late final LocalLeaguesRepository _repo;
  late final PreferencesService _prefs;
  late final LeagueAnnouncementsLocal _annRepo;

  int? _lastViewedRound;
  static String _lastRoundKey(String leagueId) =>
      'ui_last_round_$leagueId';

  int _lastSeenAnnMs = 0;
  static String _lastSeenAnnKey(String leagueId) =>
      'ui_last_seen_ann_$leagueId';

  @override
  void initState() {
    super.initState();
    _prefs = ref.read(prefsServiceProvider);
    _repo = LocalLeaguesRepository(_prefs);
    _annRepo = LeagueAnnouncementsLocal(_prefs);

    final rawRound =
        _prefs.getString(_lastRoundKey(widget.leagueId));
    _lastViewedRound = int.tryParse((rawRound ?? '').trim());

    _lastSeenAnnMs =
        _prefs.getInt(_lastSeenAnnKey(widget.leagueId)) ?? 0;
  }

  Future<void> _persistRound(int round) async {
    _lastViewedRound = round;
    if (mounted) setState(() {});
    await _prefs.setString(
        _lastRoundKey(widget.leagueId), '$round');
  }

  Future<void> _markAnnouncementsSeen(int ms) async {
    _lastSeenAnnMs = ms;
    await _prefs.setInt(_lastSeenAnnKey(widget.leagueId), ms);
  }

  Future<Map<String, dynamic>> _loadData() async {
    final league = await _repo.getLeagueById(widget.leagueId);
    if (league == null) {
      throw Exception("League not found in local storage");
    }

    final fixtures =
        await _repo.getMatches(widget.leagueId);
    final teams = await _repo.getTeams(widget.leagueId);
    final knockouts =
        await _repo.getKnockoutMatches(widget.leagueId);
    final announcements =
        await _annRepo.listForLeague(widget.leagueId);

    final currentUserId = _prefs.getCurrentUserId() ??
        _prefs.getString(
                PreferencesService.kCurrentUserIdKey) ??
        'admin_user';

    final membership = await _repo.getMembership(
      leagueId: widget.leagueId,
      userId: currentUserId,
    );

    final teamNames = {
      for (final t in teams) t.id: t.name
    };

    return {
      'league': league,
      'fixtures': fixtures,
      'teams': teams,
      'teamNames': teamNames,
      'currentUserId': currentUserId,
      'membership': membership,
      'knockouts': knockouts,
      'announcements': announcements,
    };
  }

  List<FixtureMatch> _sortedSchedule(
      List<FixtureMatch> fixtures) {
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
    final rounds = sorted
        .map((m) => m.roundNumber)
        .toSet()
        .toList()
      ..sort();
    return rounds;
  }

  /// Returns only NOT played fixtures starting from [selectedRound].
  /// Auto-advances to next round with unplayed matches.
  List<FixtureMatch> _computeUpcomingUnplayed({
    required List<FixtureMatch> sortedAll,
    required int selectedRound,
    int limit = 8,
  }) {
    final unplayed =
        sortedAll.where((m) => !m.isPlayed).toList();
    if (unplayed.isEmpty) return [];

    final roundsWithUnplayed = unplayed
        .map((m) => m.roundNumber)
        .toSet()
        .toList()
      ..sort();

    int effectiveRound = selectedRound;
    if (!roundsWithUnplayed.contains(effectiveRound)) {
      final next = roundsWithUnplayed
          .where((r) => r > selectedRound)
          .toList();
      effectiveRound =
          next.isNotEmpty ? next.first : roundsWithUnplayed.first;
    }

    // Auto-update stored round if we had to jump
    if (effectiveRound != selectedRound) {
      _persistRound(effectiveRound);
    }

    final filtered = sortedAll
        .where((m) =>
            !m.isPlayed && m.roundNumber >= effectiveRound)
        .toList();
    if (filtered.length <= limit) return filtered;
    return filtered.take(limit).toList();
  }

  @override
  Widget build(BuildContext context) {
    final primary =
        Theme.of(context).colorScheme.primary;
    final isWide =
        MediaQuery.of(context).size.width > 600;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('League Details'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: FutureBuilder<Map<String, dynamic>>(
            future: _loadData(),
            builder: (context, snapshot) {
              if (snapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: Colors.cyanAccent,
                  ),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.redAccent,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Error: ${snapshot.error}",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => setState(() {}),
                          child: const Text(
                            'Retry',
                            style: TextStyle(
                              color: Colors.cyanAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }

              final league =
                  snapshot.data!['league'] as League;
              final fixtures = snapshot
                  .data!['fixtures'] as List<FixtureMatch>;
              final teams =
                  snapshot.data!['teams'] as List<Team>;
              final teamNames =
                  snapshot.data!['teamNames']
                      as Map<String, String>;
              final membership =
                  snapshot.data!['membership']
                      as Membership?;
              final knockouts =
                  snapshot.data!['knockouts']
                      as List<KnockoutMatch>;
              final announcements =
                  snapshot.data!['announcements']
                      as List<LeagueAnnouncement>;

              final sorted = _sortedSchedule(fixtures);
              final rounds = _allRounds(sorted);
              final selectedRound =
                  (_lastViewedRound != null &&
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
              final hasUnreadAnnouncements =
                  announcements.isNotEmpty &&
                  latestAnnMs > _lastSeenAnnMs;

              if (hasUnreadAnnouncements) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _markAnnouncementsSeen(latestAnnMs);
                });
              }

              final isOwnerByLeague =
                  membership?.role ==
                      LeagueRole.organizer;
              final isOwnerFallback =
                  league.organizerUserId ==
                      (snapshot.data!['currentUserId']
                          as String);
              final isOwner =
                  isOwnerByLeague || isOwnerFallback;

              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isWide ? 600 : 500,
                ),
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  children: [
                    _overviewCard(
                      context,
                      primary,
                      league,
                      isOwner,
                    ),
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
                      fixtures,
                      teams,
                      knockouts,
                    ),
                    const SizedBox(height: 16),
                    _upcomingMatchesCard(
                      context,
                      fixtures: upcoming,
                      names: teamNames,
                      rounds: rounds,
                      selectedRound: selectedRound,
                      onRoundSelected: (r) =>
                          _persistRound(r),
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

  Widget _overviewCard(
    BuildContext context,
    Color c,
    League league,
    bool isOwner,
  ) {
    // Build rule summary pills from settings
    final settings = league.settings;

    final rulePills = <Widget>[
      _pill(
        league.isPrivate ? 'Private' : 'Public',
        Colors.cyanAccent,
      ),
      _pill(
        '${league.maxTeams} Teams Max',
        Colors.orangeAccent,
      ),
      _pill(
        league.region,
        Colors.purpleAccent,
      ),
      _pill(
        settings.doubleRoundRobin
            ? 'Double RR'
            : 'Single RR',
        Colors.lightBlueAccent,
      ),
    ];

    if (league.format == LeagueFormat.uclGroup) {
      rulePills.add(
        _pill(
          'Group Size ${settings.groupSize}',
          Colors.tealAccent,
        ),
      );
    }

    if (league.format == LeagueFormat.uclSwiss) {
      rulePills.add(
        _pill(
          'Swiss Rounds ${settings.swissRounds}',
          Colors.tealAccent,
        ),
      );
    }

    return Glass(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
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
                  message: 'Organiser',
                  child: Container(
                    padding:
                        const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent
                          .withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified_user,
                      color: Colors.cyanAccent,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${league.format.displayName} • ${league.season}',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: rulePills,
          ),
        ],
      ),
    );
  }

  Widget _announcementsCard(
    BuildContext context,
    List<LeagueAnnouncement> anns,
    bool hasUnread,
  ) {
    final sorted = anns.toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    final formatter = DateFormat('MMM d • HH:mm');
    final useMarquee = sorted.length > 1;

    return Glass(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Announcements',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
              if (hasUnread) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.8),
                    borderRadius:
                        BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      color: Colors.white,
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
              scrollDirection: Axis.horizontal,
              itemCount: sorted.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final a = sorted[index];
                final timeStr = formatter.format(
                  DateTime.fromMillisecondsSinceEpoch(
                    a.createdAtMs,
                  ),
                );
                return GlassAnnouncement(
                  title: a.title,
                  message: a.message,
                  time: timeStr,
                  marquee: useMarquee,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ... rest of file (quickActions, upcoming card, etc.) unchanged ...

  // ...rest of your original file ( _quickActions, _upcomingMatchesCard, _roundChip, _fixtureRow, _actionButton, _pill, _generateSwissKnockouts, _generateGroupKnockouts ) remains unchanged...
  
  Widget _quickActions(
    BuildContext context,
    League league,
    bool isOwner,
    List<FixtureMatch> fixtures,
    List<Team> teams,
    List<KnockoutMatch> knockouts,
  ) {
    final isSwiss =
        league.format == LeagueFormat.uclSwiss;
    final isGroup =
        league.format == LeagueFormat.uclGroup;
    final hasKnockouts = knockouts.isNotEmpty;

    void showNeedKnockoutsSnack() {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Generate the knockout bracket first.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return Glass(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            'League Menu',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.white,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.list_alt,
                  label: 'Fixtures',
                  onTap: () => context.push(
                    '/leagues/${widget.leagueId}/fixtures',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  icon: Icons.leaderboard,
                  label: 'Standings',
                  onTap: () => context.push(
                    '/leagues/${widget.leagueId}/standings',
                  ),
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
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.edit_note),
                label: const Text(
                  'MANAGE LEAGUE SCORES',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () async {
                  await context.push(
                      '/leagues/${widget.leagueId}/admin-scores');
                  if (!mounted) return;
                  setState(() {}); // refresh
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                    color: Colors.white24,
                  ),
                  foregroundColor: Colors.cyanAccent,
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.settings),
                label: const Text(
                  'LEAGUE SETTINGS (ADMIN)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                onPressed: () => context.push(
                  '/leagues/${widget.leagueId}/admin',
                ),
              ),
            ),
            if (isSwiss) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Colors.cyanAccent,
                    ),
                    foregroundColor: Colors.cyanAccent,
                    padding:
                        const EdgeInsets.symmetric(
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.emoji_events),
                  label: const Text(
                    'GENERATE KNOCKOUT BRACKET (SWISS)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  onPressed: () =>
                      _generateSwissKnockouts(
                    context,
                    league,
                    teams,
                    fixtures,
                  ),
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
                      color: Colors.cyanAccent,
                    ),
                    foregroundColor: Colors.cyanAccent,
                    padding:
                        const EdgeInsets.symmetric(
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                  ),
                  icon:
                      const Icon(Icons.emoji_events_outlined),
                  label: const Text(
                    'GENERATE KNOCKOUT BRACKET (GROUPS)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  onPressed: () =>
                      _generateGroupKnockouts(
                    context,
                    league,
                  ),
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
                        foregroundColor: hasKnockouts
                            ? Colors.cyanAccent
                            : Colors.white30,
                      ),
                      onPressed: hasKnockouts
                          ? () => context.push(
                                '/leagues/${widget.leagueId}/knockout',
                              )
                          : showNeedKnockoutsSnack,
                      icon: const Icon(
                        Icons.account_tree_outlined,
                        size: 18,
                      ),
                      label: const Text(
                        'VIEW KNOCKOUT BRACKET',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: hasKnockouts
                            ? Colors.cyanAccent
                            : Colors.white30,
                      ),
                      onPressed: hasKnockouts
                          ? () async {
                              await context.push(
                                  '/leagues/${widget.leagueId}/knockout-admin');
                              if (!mounted) return;
                              setState(() {}); // refresh
                            }
                          : showNeedKnockoutsSnack,
                      icon: const Icon(
                        Icons.sports_score,
                        size: 18,
                      ),
                      label: const Text(
                        'MANAGE KO SCORES',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
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
              padding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius:
                    BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white10,
                ),
              ),
              child: const Text(
                'View-only: You are a participant in this league.',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
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
    // Safety: only unplayed fixtures
    final unplayedFixtures =
        fixtures.where((f) => !f.isPlayed).toList();

    final unplayedRounds = rounds
        .where((r) =>
            unplayedFixtures.any(
                (f) => f.roundNumber == r))
        .toList();

    return Glass(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            'Coming Up Next',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.white,
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
                      label: 'R$r',
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
            const Padding(
              padding:
                  EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'No upcoming fixtures.',
                  style:
                      TextStyle(color: Colors.white38),
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
            alignment: Alignment.center,
            child: TextButton(
              onPressed: () => context.push(
                '/leagues/${widget.leagueId}/fixtures',
              ),
              child: const Text(
                'VIEW ALL FIXTURES',
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
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
    return InkWell(
      onTap: onTap,
      borderRadius:
          BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? Colors.cyanAccent
              : Colors.white.withOpacity(0.06),
          borderRadius:
              BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? Colors.cyanAccent
                : Colors.white10,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.black
                : Colors.white70,
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
  ) {
    final homeName =
        names[f.homeTeamId] ?? f.homeTeamId;
    final awayName =
        names[f.awayTeamId] ?? f.awayTeamId;

    return InkWell(
      onTap: () => context.push(
        '/leagues/${widget.leagueId}/matches/${f.id}',
      ),
      borderRadius:
          BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius:
              BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white10,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius:
                    BorderRadius.circular(6),
              ),
              child: Text(
                'R${f.roundNumber}',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                homeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 14,
              ),
              child: Text(
                'VS',
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Text(
                awayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              color: Colors.white38,
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
    return InkWell(
      onTap: onTap,
      borderRadius:
          BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: 16,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius:
              BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white10,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: Colors.white70,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color c) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        borderRadius:
            BorderRadius.circular(8),
        color: c.withOpacity(0.1),
        border: Border.all(
          color: c.withOpacity(0.2),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
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
    if (league.format != LeagueFormat.uclSwiss) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This action is only for Swiss leagues.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final existing =
        await _repo.getKnockoutMatches(league.id);
    if (existing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Knockout bracket already generated.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Filter only Swiss league phase matches (no groupId)
    final swissMatches = fixtures
        .where((m) => m.groupId == null)
        .toList();

    if (swissMatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No Swiss league matches found.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final roundsSet = swissMatches
        .map((m) => m.roundNumber)
        .toSet();
    if (roundsSet.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No Swiss rounds found.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final requiredRounds = league.settings.swissRounds;

    // Check that we have all rounds 1..requiredRounds
    final hasAllRounds = List.generate(
      requiredRounds,
      (i) => i + 1,
    ).every((r) => roundsSet.contains(r));

    // Check that all matches in rounds 1..requiredRounds are played
    final anyUnplayedInRequired = swissMatches
        .where((m) => m.roundNumber <= requiredRounds)
        .any((m) => !m.isPlayed);

    if (!hasAllRounds || anyUnplayedInRequired) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You must finish all $requiredRounds Swiss rounds before generating knockouts.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final swissStandings =
        StandingsCalculator.calculate(
      teams: teams,
      matches: swissMatches,
    );

    if (swissStandings.length < 16) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'At least 16 teams are required to generate Swiss knockouts.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final koMatches =
        TournamentController.seedSwissKnockouts(
      leagueId: league.id,
      swissStandings: swissStandings,
    );

    if (koMatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Failed to seed knockout bracket from Swiss standings.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await _repo.saveKnockoutMatches(
      league.id,
      koMatches,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Knockout bracket generated (Play-off + Round of 16).',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (mounted) setState(() {});
  }

  Future<void> _generateGroupKnockouts(
    BuildContext context,
    League league,
  ) async {
    if (league.format != LeagueFormat.uclGroup) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This action is only for UCL Group leagues.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final existing =
        await _repo.getKnockoutMatches(league.id);
    if (existing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Knockout bracket already generated.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final teams = await _repo.getTeams(league.id);
    final matches = await _repo.getMatches(league.id);

    // All GROUP matches must be played before generating knockouts.
    final groupMatches = matches
        .where((m) => m.groupId != null)
        .toList();

    if (groupMatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No group matches found. Generate group fixtures first.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final anyUnplayedGroup =
        groupMatches.any((m) => !m.isPlayed);
    if (anyUnplayedGroup) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You must finish all group matches before generating the knockout bracket.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Build standings from fully played groupMatches.
    final groupIds = groupMatches
        .map((m) => m.groupId)
        .whereType<String>()
        .map((g) => g.trim())
        .where((g) => g.isNotEmpty)
        .toSet();

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
      if (groupTeams.isEmpty) continue;

      final rows =
          StandingsCalculator.calculate(
        teams: groupTeams,
        matches: gm,
      );

      groupStandings[groupId] = rows;
    }

    if (groupStandings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No group standings available to seed knockouts.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final koMatches =
        TournamentController.seedKnockoutsFromGroups(
      leagueId: league.id,
      groupStandings: groupStandings,
    );

    if (koMatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Failed to seed knockout bracket from group standings.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await _repo.saveKnockoutMatches(
      league.id,
      koMatches,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Knockout bracket generated from group standings.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );

    if (mounted) setState(() {});
  }
}
