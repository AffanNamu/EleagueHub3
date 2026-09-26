import 'package:flutter/material.dart';
import '../widgets/my_fixtures_filter.dart';
import '../models/match.dart';
import '../models/team_stats.dart';
import '../logic/standings_engine.dart';
import '../presentation/knockout_bracket_screen.dart';
import '../data/leagues_repository_mock.dart'; // import repo
import '../../../core/locale/app_localizations.dart';

class LeagueDashboardScreen extends StatefulWidget {
  final String leagueId;

  const LeagueDashboardScreen({
    super.key,
    required this.leagueId,
  });

  @override
  State<LeagueDashboardScreen> createState() => _LeagueDashboardScreenState();
}

class _LeagueDashboardScreenState extends State<LeagueDashboardScreen> {
  bool filterByMe = false;

  final LeaguesRepositoryMock repo = LeaguesRepositoryMock(); // repo instance
  List<Match> _matches = [];
  List<TeamStats> _teams = [];

  @override
  void initState() {
    super.initState();
    _loadLeagueData();
  }

  /// Load teams and fixtures from repository
  void _loadLeagueData() {
    final teams = repo.standings(widget.leagueId); // TeamStats with points
    final fixtures = repo.fixtures(widget.leagueId); // Match list

    setState(() {
      _teams = teams;
      _matches = fixtures.map((f) => Match.fromFixtureMatch(f)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sortedTeams = StandingsEngine.compute(_teams, _matches);
    final standings = List<TeamStatsWithExtras>.generate(
      sortedTeams.length,
      (index) {
        final t = sortedTeams[index];
        return TeamStatsWithExtras(
          base: t,
          position: index + 1,
          teamName: _lookupTeamName(t.teamId, l10n),
        );
      },
    );

    return Scaffold(
      backgroundColor: const Color(0xFF4FC3F7),
      appBar: AppBar(
        title: Text(l10n.tr('league_dashboard_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.emoji_events),
            onPressed: _openKnockoutIfUCL,
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Device-class check (shortestSide), not available width -- a
            // phone in landscape can easily exceed 600 logical px of
            // width, which would wrongly switch it into the tablet
            // side-by-side layout.
            final isTablet = MediaQuery.of(context).size.shortestSide >= 600;

            return Column(
              children: [
                MyFixturesFilter(
                  onToggle: (val) => setState(() => filterByMe = val),
                ),
                Expanded(
                  child: isTablet
                      ? _buildTabletView(standings, l10n)
                      : _buildMobileView(standings, l10n),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// ---------------- HELPERS ----------------
  String _lookupTeamName(String teamId, AppLocalizations l10n) {
    final team = _teams.firstWhere(
      (t) => t.teamId == teamId,
      orElse: () => TeamStats.empty(teamId: teamId, leagueId: widget.leagueId),
    );
    return team.teamName.isNotEmpty
        ? team.teamName
        : "${l10n.tr('league_dashboard_team_fallback_prefix')} $teamId";
  }

  void _openKnockoutIfUCL() {
    final hasGroups = _matches.any((m) => m.groupId != null);
    if (!hasGroups) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KnockoutBracketScreen(
          matches: _matches,
          teamsById: {for (var t in _teams) t.teamId: t},
        ),
      ),
    );
  }

  /// ---------------- MOBILE ----------------
  Widget _buildMobileView(List<TeamStatsWithExtras> standings, AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _sectionTitle(l10n.tr('league_dashboard_standings_title')),
        const SizedBox(height: 10),
        _buildStandingsList(standings, l10n),
        const SizedBox(height: 30),
        _sectionTitle(l10n.tr('league_dashboard_upcoming_fixtures_title')),
        const SizedBox(height: 10),
        _buildFixturesList(l10n),
      ],
    );
  }

  /// ---------------- TABLET ----------------
  Widget _buildTabletView(List<TeamStatsWithExtras> standings, AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(l10n.tr('league_dashboard_standings_title')),
                const SizedBox(height: 10),
                _buildStandingsList(standings, l10n),
              ],
            ),
          ),
        ),
        VerticalDivider(color: Colors.white.withOpacity(0.15), width: 1),
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle(l10n.tr('league_dashboard_fixtures_title')),
                const SizedBox(height: 10),
                _buildFixturesList(l10n),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// ---------------- COMPONENTS ----------------
  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildStandingsList(List<TeamStatsWithExtras> standings, AppLocalizations l10n) {
    if (standings.isEmpty) return _emptyBox(l10n.tr('league_dashboard_no_standings_yet'));

    return Column(
      children: standings.map((team) {
        return ListTile(
          leading: Text(team.position.toString(), style: const TextStyle(color: Colors.white)),
          title: Text(team.teamName, style: const TextStyle(color: Colors.white)),
          trailing: Text("${team.base.points} pts",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        );
      }).toList(),
    );
  }

  Widget _buildFixturesList(AppLocalizations l10n) {
    final fixtures = filterByMe ? _matches.where((m) => m.isMyMatch).toList() : _matches;

    if (fixtures.isEmpty) return _emptyBox(l10n.tr('league_dashboard_no_fixtures_available'));

    return Column(
      children: fixtures.map((match) {
        return ListTile(
          title: Text("${match.homeTeamName} vs ${match.awayTeamName}", style: const TextStyle(color: Colors.white)),
          subtitle: Text(match.isPlayed ? l10n.tr('league_dashboard_match_finished') : l10n.tr('league_dashboard_match_upcoming'), style: const TextStyle(color: Colors.white70)),
          trailing: match.isPlayed
              ? Text("${match.homeScore} - ${match.awayScore}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
              : const Icon(Icons.chevron_right, color: Colors.white54),
        );
      }).toList(),
    );
  }

  Widget _emptyBox(String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
      child: Center(child: Text(message, style: const TextStyle(color: Colors.white70))),
    );
  }
}

/// Helper wrapper to attach position & teamName to TeamStats
class TeamStatsWithExtras {
  final TeamStats base;
  final int position;
  final String teamName;

  TeamStatsWithExtras({
    required this.base,
    required this.position,
    required this.teamName,
  });
}
