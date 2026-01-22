import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/leagues_repository_local.dart';
import '../models/knockout_match.dart';
import '../models/team.dart';
import '../models/enums.dart';

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
  List<KnockoutMatch> _matches = [];
  Map<String, Team> _teamsById = {};

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

  @override
  Widget build(BuildContext context) {
    final rounds = <String, List<KnockoutMatch>>{};
    for (var m in _matches) {
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

    return GlassScaffold(
      appBar: AppBar(
        title: Text(
          'CHAMPIONS BRACKET',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.sync_rounded, color: Colors.cyanAccent),
            tooltip: 'Reload bracket',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _matches.isEmpty
                  ? Center(
                      child: Glass(
                        padding: const EdgeInsets.all(32),
                        borderRadius: 24,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.emoji_events_outlined,
                              size: 48,
                              color: Colors.white24,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Brackets not generated yet.\nGenerate via Admin panel.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        const SizedBox(height: 10),
                        _buildHeaderInfo(),
                        const SizedBox(height: 16),
                        Expanded(
                          child: InteractiveViewer(
                            constrained: false,
                            boundaryMargin: const EdgeInsets.all(150),
                            minScale: 0.2,
                            maxScale: 2.0,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 20),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var i = 0;
                                      i < roundNames.length;
                                      i++) ...[
                                    _buildRoundColumn(
                                      roundNames[i],
                                      rounds[roundNames[i]]!,
                                    ),
                                    if (i < roundNames.length - 1)
                                      _buildBracketConnector(),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }

  Widget _buildHeaderInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border:
            const Border(left: BorderSide(color: Colors.cyanAccent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'UCL TOURNAMENT PHASE',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            '${_matches.length} matches scheduled • Pinch to explore',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundColumn(String title, List<KnockoutMatch> roundMatches) {
    return Column(
      children: [
        Container(
          width: 240,
          margin: const EdgeInsets.only(bottom: 24),
          padding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white10),
          ),
          child: Text(
            title.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ),
        ...roundMatches.map((m) => _buildMatchCard(m)).toList(),
      ],
    );
  }

  Widget _buildMatchCard(KnockoutMatch match) {
    final homeTeam =
        match.homeTeamId != null ? _teamsById[match.homeTeamId] : null;
    final awayTeam =
        match.awayTeamId != null ? _teamsById[match.awayTeamId] : null;

    final homeName = homeTeam?.name ?? (match.homeTeamId ?? 'TBD');
    final awayName = awayTeam?.name ?? (match.awayTeamId ?? 'TBD');

    final isHomeWinner = match.homeScore != null &&
        match.awayScore != null &&
        match.homeScore! > match.awayScore!;
    final isAwayWinner = match.homeScore != null &&
        match.awayScore != null &&
        match.awayScore! > match.homeScore!;

    final isTBD = match.homeTeamId == null || match.awayTeamId == null;

    return Container(
      width: 240,
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      child: Stack(
        children: [
          Glass(
            borderRadius: 12,
            padding: const EdgeInsets.all(1), // Border width
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                gradient: LinearGradient(
                  colors: [
                    isTBD
                        ? Colors.white10
                        : Colors.cyanAccent.withOpacity(0.1),
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
                    _buildTeamRow(
                      homeName,
                      match.homeScore?.toString() ?? "-",
                      isHomeWinner,
                    ),
                    const SizedBox(height: 8),
                    Divider(
                      color: Colors.white.withOpacity(0.05),
                      height: 1,
                    ),
                    const SizedBox(height: 8),
                    _buildTeamRow(
                      awayName,
                      match.awayScore?.toString() ?? "-",
                      isAwayWinner,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: isTBD ? Colors.white24 : Colors.cyanAccent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamRow(String name, String score, bool isWinner) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isWinner
                  ? Colors.cyanAccent
                  : (score == "-" ? Colors.white38 : Colors.white),
              fontSize: 13,
              fontWeight: isWinner ? FontWeight.w900 : FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color:
                isWinner ? Colors.cyanAccent.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            score,
            style: TextStyle(
              color: isWinner ? Colors.cyanAccent : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBracketConnector() {
    return Container(
      width: 40,
      margin: const EdgeInsets.only(top: 100),
      child: Center(
        child: Container(
          height: 1,
          width: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.cyanAccent.withOpacity(0.5),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
