import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../data/leagues_repository_local.dart';
import '../models/league_format.dart';
import '../models/team.dart';
import '../models/fixture_match.dart';
import '../domain/algorithms/round_robin.dart';
import '../domain/algorithms/swiss_pairing.dart';

class AddTeamsScreen extends ConsumerStatefulWidget {
  final String leagueId;
  final LeagueFormat format;

  const AddTeamsScreen({
    super.key,
    required this.leagueId,
    required this.format,
  });

  @override
  ConsumerState<AddTeamsScreen> createState() => _AddTeamsScreenState();
}

class _AddTeamsScreenState extends ConsumerState<AddTeamsScreen> {
  late LocalLeaguesRepository _localRepo;

  /// Bulk text entry controller
  final _bulkController = TextEditingController();

  /// New teams being added in this session (name + group label)
  final List<Map<String, String>> _tempTeams = [];

  /// Teams already saved for this league
  List<Team> _existingTeams = [];

  bool _isLoading = true;

  String _selectedGroup = 'Group A';
  final List<String> _groups = const [
    'Group A',
    'Group B',
    'Group C',
    'Group D',
    'Group E',
    'Group F',
    'Group G',
    'Group H',
  ];

  /// Max teams allowed in this Add Teams session, based on league format.
  int get _maxTeamsForFormat {
    switch (widget.format) {
      case LeagueFormat.classic:
        return 20;
      case LeagueFormat.uclGroup:
      case LeagueFormat.uclSwiss:
        return 32;
    }
  }

  @override
  void initState() {
    super.initState();
    _localRepo = LocalLeaguesRepository(ref.read(prefsServiceProvider));
    _loadExistingTeams();
  }

  @override
  void dispose() {
    _bulkController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingTeams() async {
    final teams = await _localRepo.getTeams(widget.leagueId);
    if (!mounted) return;
    setState(() {
      _existingTeams = teams;
      _isLoading = false;
    });
  }

  void _addTeam(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    // Total teams after adding this one
    final totalCurrent =
        _existingTeams.length + _tempTeams.length;

    // Enforce max teams per format across saved + new
    if (totalCurrent >= _maxTeamsForFormat) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maximum $_maxTeamsForFormat teams allowed for this format.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Avoid duplicates in this session
    if (_tempTeams.any((t) => t['name'] == trimmed)) return;

    // Avoid duplicates vs existing saved teams (by name)
    if (_existingTeams.any(
      (t) => t.name.toLowerCase() == trimmed.toLowerCase(),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A team with this name already exists.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _tempTeams.add({
        'name': trimmed,
        'group': widget.format == LeagueFormat.uclGroup
            ? _selectedGroup
            : 'League Pool',
      });

      // Rotate group automatically for group format
      if (widget.format == LeagueFormat.uclGroup) {
        final next =
            (_groups.indexOf(_selectedGroup) + 1) % _groups.length;
        _selectedGroup = _groups[next];
      }
    });
  }

  /// When user taps "ADD TEAMS TO PREVIEW", show a popup to preview the names
  /// that will be added, so mistakes are visible.
  void _importBulk() {
    final text = _bulkController.text;
    if (text.isEmpty) return;

    // Parse candidate names
    final rawNames = text.split(RegExp(r'[,\n]'));
    final names = rawNames
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList();

    if (names.isEmpty) return;

    FocusScope.of(context).unfocus();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Preview teams to add',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Review the team names below. Duplicates or teams over the limit will be skipped automatically.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 260,
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: names.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final name = names[index];
                              return Glass(
                                borderRadius: 16,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 13,
                                        backgroundColor: Colors
                                            .cyanAccent
                                            .withOpacity(0.18),
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            color:
                                                Colors.cyanAccent,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                          overflow:
                                              TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () =>
                                    Navigator.of(ctx).pop(),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () {
                                  // Actually add teams using the same logic
                                  // as single _addTeam, so max + duplicates
                                  // are still enforced.
                                  for (final n in names) {
                                    _addTeam(n);
                                  }
                                  _bulkController.clear();
                                  Navigator.of(ctx).pop();
                                },
                                child: const Text('Add to preview'),
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
          ),
        );
      },
    );
  }

  Future<void> _generateAndSave() async {
    if (_tempTeams.isEmpty && _existingTeams.isEmpty) {
      // Nothing to save
      if (mounted) {
        context.go('/leagues/${widget.leagueId}');
      }
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    // Create Team objects for all new teams in this session
    final newTeams = _tempTeams.map((t) {
      return Team(
        id: const Uuid().v4(),
        leagueId: widget.leagueId,
        name: t['name']!,
        updatedAtMs: now,
        version: 1,
      );
    }).toList();

    // Combine existing + new teams, so we don't wipe old ones
    final allTeams = [..._existingTeams, ...newTeams];

    await _localRepo.saveTeams(widget.leagueId, allTeams);

    List<FixtureMatch> generatedFixtures = [];

    // IMPORTANT: For now we only support full re-generation for classic leagues.
    if (widget.format == LeagueFormat.classic) {
      final teamIds = allTeams.map((t) => t.id).toList();
      generatedFixtures = RoundRobinGenerator.generate(
        leagueId: widget.leagueId,
        teamIds: teamIds,
        doubleRoundRobin: true,
        startRoundNumber: 1,
      );
    } else {
      // For UCL Group and Swiss, we currently do not support re-generating
      // fixtures after teams have been added once, because group/swiss
      // seeding requires more data than Team currently stores.
      // We keep existing fixtures in those formats.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Adding teams after fixtures exist is only supported for classic leagues right now.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    if (generatedFixtures.isNotEmpty) {
      // Replace existing fixtures with the new schedule
      await _localRepo.replaceMatches(
        widget.leagueId,
        generatedFixtures,
      );
    }

    if (mounted) {
      context.go('/leagues/${widget.leagueId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    return GlassScaffold(
      appBar: AppBar(
        title: Text('Add Teams · ${widget.format.displayName}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 600 : 500),
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.cyanAccent,
                    ),
                  )
                : Column(
                    children: [
                      if (widget.format == LeagueFormat.uclGroup)
                        _buildGroupSelector(),
                      Expanded(
                        child: _buildBulkEntry(),
                      ),
                      Flexible(
                        flex: 2,
                        child: _buildPreviewPanel(),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Glass(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            const Text('Assign to', style: TextStyle(color: Colors.white70)),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedGroup,
                  dropdownColor: const Color(0xFF000428),
                  style: const TextStyle(color: Colors.cyanAccent),
                  isExpanded: true,
                  items: _groups
                      .map(
                        (g) => DropdownMenuItem(
                          value: g,
                          child: Text(g),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedGroup = v!),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBulkEntry() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Glass(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Team names',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _bulkController,
                maxLines: null,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText:
                      'Type or paste team names (comma or new line separated).\nExample:\nTeam A\nTeam B\nTeam C',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FilledButton(
                onPressed: _importBulk,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  backgroundColor: Colors.white.withOpacity(0.12),
                ),
                child: const Text('ADD TEAMS TO PREVIEW'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewPanel() {
    final existingCount = _existingTeams.length;
    final newCount = _tempTeams.length;
    final totalCount = existingCount + newCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Glass(
        borderRadius: 28,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SectionHeader('Team Preview'),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 2, left: 16, right: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Saved: $existingCount · New: $newCount',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 16, right: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$totalCount / $_maxTeamsForFormat teams total',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: existingCount + newCount,
                itemBuilder: (context, i) {
                  if (i < existingCount) {
                    final team = _existingTeams[i];
                    return _buildTeamTile(
                      index: i,
                      name: team.name,
                      label: 'Saved',
                      isNew: false,
                    );
                  } else {
                    final idx = i - existingCount;
                    final team = _tempTeams[idx];
                    final group = team['group'] ?? '';
                    final label = group.isEmpty ? 'New' : 'New · $group';
                    return _buildTeamTile(
                      index: i,
                      name: team['name']!,
                      label: label,
                      isNew: true,
                    );
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton(
                onPressed: _generateAndSave,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('SAVE & GENERATE FIXTURES'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamTile({
    required int index,
    required String name,
    required String label,
    required bool isNew,
  }) {
    return Card(
      color: isNew
          ? Colors.cyanAccent.withOpacity(0.10)
          : Colors.white.withOpacity(0.04),
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 14,
          backgroundColor:
              isNew ? Colors.cyanAccent.withOpacity(0.18) : Colors.white12,
          child: Text(
            '${index + 1}',
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isNew
                ? Colors.cyanAccent.withOpacity(0.25)
                : Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
