// lib/features/football_hub/presentation/football_standings_screen.dart

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/football_api_service.dart';
import '../models/football_standing.dart';

class FootballStandingsScreen extends StatefulWidget {
  const FootballStandingsScreen({
    super.key,
    required this.leagueId,
    required this.season,
    required this.leagueName,
  });

  final int leagueId;
  final int season;
  final String leagueName;

  @override
  State<FootballStandingsScreen> createState() => _FootballStandingsScreenState();
}

class _FootballStandingsScreenState extends State<FootballStandingsScreen> {
  final _service = FootballApiService();
  late Future<FootballStandingsTable?> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.getStandings(leagueId: widget.leagueId, season: widget.season);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(widget.leagueName),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: FutureBuilder<FootballStandingsTable?>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load standings.\n${snap.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.secondaryText(brightness)),
                  ),
                ),
              );
            }
            final table = snap.data;
            if (table == null || table.rows.isEmpty) {
              return Center(
                child: Text(
                  'No standings available yet.',
                  style: TextStyle(color: AppTheme.secondaryText(brightness)),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
              itemCount: table.groups.length,
              itemBuilder: (context, groupIndex) {
                final rows = table.groups[groupIndex];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Glass(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HeaderRow(brightness: brightness),
                        const SizedBox(height: 4),
                        ...rows.map((r) => _StandingRowWidget(row: r, brightness: brightness)),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.brightness});
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: AppTheme.secondaryText(brightness),
    );
    return Row(
      children: [
        SizedBox(width: 24, child: Text('#', style: style)),
        const SizedBox(width: 8),
        Expanded(child: Text('TEAM', style: style)),
        SizedBox(width: 28, child: Text('P', textAlign: TextAlign.center, style: style)),
        SizedBox(width: 28, child: Text('GD', textAlign: TextAlign.center, style: style)),
        SizedBox(width: 32, child: Text('PTS', textAlign: TextAlign.center, style: style)),
      ],
    );
  }
}

class _StandingRowWidget extends StatelessWidget {
  const _StandingRowWidget({required this.row, required this.brightness});
  final FootballStandingRow row;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final nameStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: AppTheme.primaryText(brightness),
    );
    final numStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppTheme.secondaryText(brightness),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text('${row.rank}', style: numStyle.copyWith(color: AppTheme.primaryText(brightness))),
          ),
          const SizedBox(width: 8),
          if (row.teamLogoUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                row.teamLogoUrl,
                width: 20,
                height: 20,
                errorBuilder: (_, __, ___) => const SizedBox(width: 20, height: 20),
              ),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(row.teamName, style: nameStyle, overflow: TextOverflow.ellipsis),
          ),
          SizedBox(width: 28, child: Text('${row.played}', textAlign: TextAlign.center, style: numStyle)),
          SizedBox(
            width: 28,
            child: Text(
              row.goalsDiff > 0 ? '+${row.goalsDiff}' : '${row.goalsDiff}',
              textAlign: TextAlign.center,
              style: numStyle,
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '${row.points}',
              textAlign: TextAlign.center,
              style: nameStyle,
            ),
          ),
        ],
      ),
    );
  }
}
