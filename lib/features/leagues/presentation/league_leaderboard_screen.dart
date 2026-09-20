import 'package:flutter/material.dart';
import 'dart:ui';
import '../../models/league_format.dart';
import '../data/leagues_repository_mock.dart';
import '../models/team_stats.dart';
import '../../../core/locale/app_localizations.dart';

class LeagueLeaderboardScreen extends StatefulWidget {
  final LeagueFormat format;
  final String leagueId;
  final String leagueName;

  const LeagueLeaderboardScreen({
    super.key,
    required this.format,
    required this.leagueId,
    required this.leagueName,
  });

  @override
  State<LeagueLeaderboardScreen> createState() => _LeagueLeaderboardScreenState();
}

class _LeagueLeaderboardScreenState extends State<LeagueLeaderboardScreen> {
  final LeaguesRepositoryMock repo = LeaguesRepositoryMock();
  List<TeamStats> _teams = [];

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  void _loadTeams() {
    final teams = repo.standings(widget.leagueId); // get teams with points
    setState(() {
      _teams = teams;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: const Color(0xFF4FC3F7),
      appBar: AppBar(
        title: Text('${widget.leagueName} ${l10n.tr('league_leaderboard_standings_suffix')}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: widget.format == LeagueFormat.uclGroup
            ? _buildGroupView(l10n)
            : _buildSingleTableView(l10n),
      ),
    );
  }

  /// ---------------- GROUP VIEW ----------------
  Widget _buildGroupView(AppLocalizations l10n) {
    final groups = <String, List<TeamStats>>{};
    for (int i = 0; i < _teams.length; i++) {
      String group = "${l10n.tr('league_leaderboard_group_label_prefix')} ${String.fromCharCode(65 + (i ~/ 4))}";
      groups.putIfAbsent(group, () => []);
      groups[group]!.add(_teams[i]);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: groups.entries.map((entry) {
        final groupTeams = entry.value;
        groupTeams.sort((a, b) => b.points.compareTo(a.points)); // descending points

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                child: Text(
                  entry.key,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              _buildGlassTable(groupTeams),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// ---------------- SINGLE TABLE VIEW ----------------
  Widget _buildSingleTableView(AppLocalizations l10n) {
    final teams = [..._teams];
    teams.sort((a, b) => b.points.compareTo(a.points));

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildTableHead(l10n),
          const SizedBox(height: 8),
          Expanded(child: _buildGlassTable(teams)),
        ],
      ),
    );
  }

  Widget _buildTableHead(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Expanded(flex: 1, child: Text("#", style: TextStyle(color: Colors.white60, fontSize: 12))),
          Expanded(flex: 4, child: Text(l10n.tr('league_leaderboard_column_team'), style: const TextStyle(color: Colors.white60, fontSize: 12))),
          Expanded(child: Text(l10n.tr('league_leaderboard_column_played'), style: const TextStyle(color: Colors.white60, fontSize: 12))),
          Expanded(child: Text(l10n.tr('league_leaderboard_column_goal_difference'), style: const TextStyle(color: Colors.white60, fontSize: 12))),
          Expanded(child: Text(l10n.tr('league_leaderboard_column_points'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildGlassTable(List<TeamStats> teams) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: teams.length,
            separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.1), height: 1),
            itemBuilder: (_, index) => _buildTeamRow(index + 1, teams[index]),
          ),
        ),
      ),
    );
  }

  Widget _buildTeamRow(int rank, TeamStats team) {
    bool isQualified = rank <= 2; // highlight top 2 for UCL/Swiss
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 1, child: Text("$rank", style: TextStyle(color: isQualified ? Colors.cyanAccent : Colors.white70))),
          Expanded(flex: 4, child: Text(team.teamName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
          Expanded(child: Text("${team.played}", style: const TextStyle(color: Colors.white70))),
          Expanded(child: Text("${team.gd}", style: const TextStyle(color: Colors.white70))),
          Expanded(child: Text("${team.points}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}
