import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../data/leagues_repository_local.dart';
import '../domain/algorithms/swiss_pairing.dart';
import '../models/enums.dart';
import '../models/fixture_match.dart';
import '../models/league_format.dart';

class FixturesScreen extends ConsumerStatefulWidget {
  final String leagueId;

  const FixturesScreen({
    super.key,
    required this.leagueId,
  });

  @override
  ConsumerState<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends ConsumerState<FixturesScreen> {
  int _selectedRound = 1;

  late LocalLeaguesRepository _repo;
  late PreferencesService _prefs;

  Map<String, String> _teamNames = {};
  bool _isLoading = true;

  LeagueFormat _format = LeagueFormat.classic;
  List<String> _groups = [];

  /// null = "All groups" when format == uclGroup
  String? _selectedGroup;

  bool _isGeneratingNextRound = false;

  static String _lastRoundKey(String leagueId) => 'ui_last_round_$leagueId';
  static String _lastGroupKey(String leagueId) => 'ui_last_group_$leagueId';

  @override
  void initState() {
    super.initState();
    _prefs = ref.read(prefsServiceProvider);
    _repo = LocalLeaguesRepository(_prefs);

    // Restore last viewed round (shared with LeagueDetailScreen)
    final savedRoundRaw = _prefs.getString(_lastRoundKey(widget.leagueId));
    final savedRound = int.tryParse((savedRoundRaw ?? '').trim());
    if (savedRound != null && savedRound >= 1) {
      _selectedRound = savedRound;
    }

    // Restore last selected group (only matters for UCL Group format; we apply after loading groups)
    final savedGroupRaw = _prefs.getString(_lastGroupKey(widget.leagueId));
    _selectedGroup = (savedGroupRaw == null || savedGroupRaw.trim().isEmpty) ? null : savedGroupRaw.trim();

    _loadInitialData();
  }

  void _persistRound(int round) {
    _prefs.setString(_lastRoundKey(widget.leagueId), '$round');
  }

  void _persistGroup(String? group) {
    // null/"All" stored as empty string
    _prefs.setString(_lastGroupKey(widget.leagueId), group ?? '');
  }

  void _setRound(int round) {
    setState(() => _selectedRound = round);
    _persistRound(round);
  }

  void _setGroup(String? group) {
    setState(() {
      _selectedGroup = group;
      _selectedRound = 1; // reset round on filter change
    });
    _persistGroup(group);
    _persistRound(1);
  }

  Future<void> _loadInitialData() async {
    try {
      final leagueFuture = _repo.getLeagueById(widget.leagueId);
      final teamsFuture = _repo.getTeams(widget.leagueId);
      final matchesFuture = _repo.getMatches(widget.leagueId);

      final league = await leagueFuture;
      final teams = await teamsFuture;
      final allMatches = await matchesFuture;

      final format = league?.format ?? LeagueFormat.classic;

      // Build groups list if needed
      List<String> groups = [];
      if (format == LeagueFormat.uclGroup) {
        groups = allMatches
            .map((m) => m.groupId)
            .whereType<String>()
            .map((g) => g.trim())
            .where((g) => g.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
      }

      // Validate restored group:
      // - Only keep it if format is uclGroup AND it exists in groups.
      // - Else fallback to "All" (null).
      String? validatedGroup;
      if (format == LeagueFormat.uclGroup) {
        final g = _selectedGroup;
        if (g != null && g.isNotEmpty && groups.contains(g)) {
          validatedGroup = g;
        } else {
          validatedGroup = null;
        }
      } else {
        validatedGroup = null;
      }

      // Compute max round under the selected group filter (important!)
      Iterable<FixtureMatch> filteredForRounds = allMatches;
      if (format == LeagueFormat.uclGroup && validatedGroup != null) {
        filteredForRounds = filteredForRounds.where((m) => m.groupId == validatedGroup);
      }

      final filteredList = filteredForRounds.toList();
      final maxRound = filteredList.isEmpty ? 1 : filteredList.map((m) => m.roundNumber).reduce((a, b) => a > b ? a : b);

      // Clamp round if user had a round larger than the group allows
      var roundToUse = _selectedRound;
      if (roundToUse > maxRound) roundToUse = maxRound;
      if (roundToUse < 1) roundToUse = 1;

      if (!mounted) return;
      setState(() {
        _format = format;
        _teamNames = {for (var t in teams) t.id: t.name};
        _groups = groups;
        _selectedGroup = validatedGroup;
        _selectedRound = roundToUse;
        _isLoading = false;
      });

      // Persist any normalization we did (clamp/group invalid)
      _persistGroup(_selectedGroup);
      _persistRound(_selectedRound);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<FixtureMatch>> _getMatches() async {
    final allMatches = await _repo.getMatches(widget.leagueId);

    Iterable<FixtureMatch> filtered = allMatches;

    if (_format == LeagueFormat.uclGroup && _selectedGroup != null) {
      filtered = filtered.where((m) => m.groupId == _selectedGroup);
    }

    filtered = filtered.where((m) => m.roundNumber == _selectedRound);

    return filtered.toList();
  }

  Future<int> _getTotalRounds() async {
    final allMatches = await _repo.getMatches(widget.leagueId);

    Iterable<FixtureMatch> filtered = allMatches;

    if (_format == LeagueFormat.uclGroup && _selectedGroup != null) {
      filtered = filtered.where((m) => m.groupId == _selectedGroup);
    }

    final list = filtered.toList();
    if (list.isEmpty) return 0;

    return list.map((m) => m.roundNumber).reduce((a, b) => a > b ? a : b);
  }

  /// Generate the next Swiss round (or Round 1 if none exist yet) for UCL Swiss leagues.
  Future<void> _generateNextSwissRound() async {
    if (_isGeneratingNextRound || _format != LeagueFormat.uclSwiss) return;

    setState(() => _isGeneratingNextRound = true);
    try {
      final league = await _repo.getLeagueById(widget.leagueId);
      if (league == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('League not found'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final maxRounds = league.settings.swissRounds;

      final teams = await _repo.getTeams(widget.leagueId);
      if (teams.length < 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Not enough teams to generate Swiss pairings.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final existingMatches = await _repo.getMatches(widget.leagueId);

      int currentMaxRound = 0;
      if (existingMatches.isNotEmpty) {
        currentMaxRound = existingMatches.map((m) => m.roundNumber).reduce((a, b) => a > b ? a : b);
      }

      int nextRound;
      List<FixtureMatch> newFixtures;

      if (currentMaxRound == 0) {
        nextRound = 1;
        newFixtures = SwissPairingEngine.generateInitialRound(
          leagueId: widget.leagueId,
          teams: teams,
          roundNumber: nextRound,
        );
      } else {
        if (currentMaxRound >= maxRounds) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('All $maxRounds Swiss rounds have already been generated.'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }

        nextRound = currentMaxRound + 1;
        newFixtures = SwissPairingEngine.generateNextRound(
          leagueId: widget.leagueId,
          teams: teams,
          existingMatches: existingMatches,
          nextRoundNumber: nextRound,
        );
      }

      if (newFixtures.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No Swiss pairings could be generated.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      await _repo.saveMatches(widget.leagueId, newFixtures);

      if (!mounted) return;

      // Persist this as the round user is currently viewing
      _setRound(nextRound);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Swiss round $nextRound generated'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      await _loadInitialData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate Swiss round: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingNextRound = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width > 700;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Fixtures & Results'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          if (_format == LeagueFormat.uclSwiss)
            IconButton(
              onPressed: _isGeneratingNextRound ? null : _generateNextSwissRound,
              tooltip: 'Generate next Swiss round',
              icon: _isGeneratingNextRound
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.cyanAccent,
                      ),
                    )
                  : const Icon(Icons.auto_mode),
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
                  constraints: BoxConstraints(maxWidth: isTablet ? 800 : 600),
                  child: FutureBuilder<int>(
                    future: _getTotalRounds(),
                    builder: (context, snapshot) {
                      final totalRounds = snapshot.data ?? 0;

                      // Clamp selected round if filter changed
                      if (totalRounds > 0 && _selectedRound > totalRounds) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _setRound(totalRounds);
                        });
                      }

                      return Column(
                        children: [
                          if (_format == LeagueFormat.uclGroup && _groups.isNotEmpty) _buildGroupSelector(),
                          if (totalRounds > 0) _buildRoundSelector(totalRounds),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: SectionHeader('Matchday Schedule'),
                          ),
                          Expanded(child: _buildMatchesList()),
                        ],
                      );
                    },
                  ),
                ),
              ),
      ),
    );
  }

  /// Horizontal chips for "All" and each group (Group A, Group B, ...).
  /// _selectedGroup == null means "All groups".
  Widget _buildGroupSelector() {
    final bool allSelected = _selectedGroup == null;

    return Container(
      height: 44,
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          GestureDetector(
            onTap: () => _setGroup(null),
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: allSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: allSelected ? Colors.cyanAccent : Colors.white10,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                'All',
                style: TextStyle(
                  color: allSelected ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          for (final group in _groups)
            Builder(
              builder: (context) {
                final isSelected = _selectedGroup == group;
                return GestureDetector(
                  onTap: () => _setGroup(group),
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isSelected ? Colors.cyanAccent : Colors.white10,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      group,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRoundSelector(int totalRounds) {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: totalRounds,
        itemBuilder: (context, i) {
          final round = i + 1;
          final isSelected = _selectedRound == round;

          return GestureDetector(
            onTap: () => _setRound(round),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? Colors.cyanAccent : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? Colors.cyanAccent : Colors.white10,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                'RD $round',
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMatchesList() {
    return FutureBuilder<List<FixtureMatch>>(
      future: _getMatches(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.cyanAccent),
          );
        }

        final matches = snapshot.data ?? [];

        if (matches.isEmpty) {
          return const Center(
            child: Text(
              'No matches generated yet',
              style: TextStyle(color: Colors.white38),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: matches.length,
          itemBuilder: (context, index) => _buildMatchCard(matches[index]),
        );
      },
    );
  }

  Widget _buildMatchCard(FixtureMatch match) {
    final homeName = _teamNames[match.homeTeamId] ?? 'TBD';
    final awayName = _teamNames[match.awayTeamId] ?? 'TBD';
    final groupLabel = match.groupId?.trim().isNotEmpty == true ? match.groupId!.trim() : null;

    return GestureDetector(
      onTap: () => context.push('/leagues/${widget.leagueId}/matches/${match.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Glass(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_format == LeagueFormat.uclGroup && groupLabel != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      groupLabel,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      homeName,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    width: 80,
                    alignment: Alignment.center,
                    child: (match.status == MatchStatus.completed || match.status == MatchStatus.played)
                        ? Text(
                            '${match.homeScore} - ${match.awayScore}',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          )
                        : const Text(
                            'VS',
                            style: TextStyle(
                              color: Colors.white24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                  Expanded(
                    child: Text(
                      awayName,
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
