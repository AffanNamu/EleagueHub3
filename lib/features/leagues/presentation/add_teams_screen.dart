import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/leagues_repository_local.dart';
import '../domain/algorithms/round_robin.dart';
import '../domain/algorithms/swiss_pairing.dart';
import '../models/fixture_match.dart';
import '../models/league_format.dart';
import '../models/team.dart';

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

  final _bulkController = TextEditingController();

  final List<Map<String, String>> _tempTeams = [];
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

  String? _bulkError;

  int get _maxTeamsForFormat {
    switch (widget.format) {
      case LeagueFormat.classic:
        return 20;
      case LeagueFormat.uclGroup:
      case LeagueFormat.uclSwiss:
        return 36;
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

  String _groupLabelForTeam(Team t) {
    if (widget.format == LeagueFormat.uclGroup) {
      return t.groupId ?? 'Unassigned';
    }
    return 'League Pool';
  }

  void _addTeam(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final totalCurrent = _existingTeams.length + _tempTeams.length;
    if (totalCurrent >= _maxTeamsForFormat) {
      setState(() {
        _bulkError = 'Maximum $_maxTeamsForFormat teams allowed for this format.';
      });
      return;
    }

    if (_tempTeams.any((t) => (t['name'] ?? '').toLowerCase() == trimmed.toLowerCase())) return;

    if (_existingTeams.any((t) => t.name.toLowerCase() == trimmed.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A team with this name already exists.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _bulkError = null;
      _tempTeams.add({
        'name': trimmed,
        'group': widget.format == LeagueFormat.uclGroup ? _selectedGroup : 'League Pool',
      });

      if (widget.format == LeagueFormat.uclGroup) {
        final next = (_groups.indexOf(_selectedGroup) + 1) % _groups.length;
        _selectedGroup = _groups[next];
      }
    });
  }

  void _importBulk() {
    final text = _bulkController.text;
    if (text.isEmpty) return;

    final names = text
        .split(RegExp(r'[,\n]'))
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
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom).add(const EdgeInsets.all(16)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                          'Review the names below. Duplicates or teams above the limit will be skipped automatically when adding.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 260),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: names.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final name = names[index];
                              return Glass(
                                borderRadius: 16,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 13,
                                        backgroundColor: Colors.cyanAccent.withOpacity(0.18),
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            color: Colors.cyanAccent,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: const TextStyle(color: Colors.white),
                                          overflow: TextOverflow.ellipsis,
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
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton(
                                onPressed: () {
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
      if (mounted) context.go('/leagues/${widget.leagueId}');
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    final newTeams = _tempTeams.map<Team>((t) {
      final groupName = t['group']!;
      final String? groupId = widget.format == LeagueFormat.uclGroup ? groupName : null;

      return Team(
        id: const Uuid().v4(),
        leagueId: widget.leagueId,
        name: t['name']!,
        groupId: groupId,
        updatedAtMs: now,
        version: 1,
      );
    }).toList();

    final allTeams = <Team>[..._existingTeams, ...newTeams];

    await _localRepo.saveTeams(widget.leagueId, allTeams);

    final existingFixtures = await _localRepo.getMatches(widget.leagueId);
    List<FixtureMatch> generatedFixtures = [];

    if (existingFixtures.isEmpty) {
      if (widget.format == LeagueFormat.classic) {
        final teamIds = allTeams.map((t) => t.id).toList();
        generatedFixtures = RoundRobinGenerator.generate(
          leagueId: widget.leagueId,
          teamIds: teamIds,
          doubleRoundRobin: true,
          startRoundNumber: 1,
        );
      } else if (widget.format == LeagueFormat.uclGroup) {
        for (final groupName in _groups) {
          final groupTeams = allTeams.where((t) => t.groupId == groupName).map((t) => t.id).toList();
          if (groupTeams.isNotEmpty) {
            generatedFixtures.addAll(
              RoundRobinGenerator.generate(
                leagueId: widget.leagueId,
                teamIds: groupTeams,
                doubleRoundRobin: true,
                groupId: groupName,
                startRoundNumber: 1,
              ),
            );
          }
        }
      } else if (widget.format == LeagueFormat.uclSwiss) {
        generatedFixtures = SwissPairingEngine.generateInitialRound(
          leagueId: widget.leagueId,
          teams: allTeams,
          roundNumber: 1,
        );
      }
    } else {
      // Re-generation
      if (widget.format == LeagueFormat.classic) {
        final teamIds = allTeams.map((t) => t.id).toList();
        generatedFixtures = RoundRobinGenerator.generate(
          leagueId: widget.leagueId,
          teamIds: teamIds,
          doubleRoundRobin: true,
          startRoundNumber: 1,
        );
      } else if (widget.format == LeagueFormat.uclGroup) {
        for (final groupName in _groups) {
          final groupTeams = allTeams.where((t) => t.groupId == groupName).map((t) => t.id).toList();
          if (groupTeams.isNotEmpty) {
            generatedFixtures.addAll(
              RoundRobinGenerator.generate(
                leagueId: widget.leagueId,
                teamIds: groupTeams,
                doubleRoundRobin: true,
                groupId: groupName,
                startRoundNumber: 1,
              ),
            );
          }
        }

        if (generatedFixtures.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Group fixtures regenerated. Previous results were reset.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else if (widget.format == LeagueFormat.uclSwiss) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Adding teams after fixtures exist is not supported for Swiss leagues.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    if (generatedFixtures.isNotEmpty) {
      await _localRepo.replaceMatches(widget.leagueId, generatedFixtures);
    }

    if (mounted) {
      context.go('/leagues/${widget.leagueId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final showTwoPane = width >= 900;

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
            constraints: BoxConstraints(maxWidth: showTwoPane ? 980 : 620),
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.cyanAccent),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Glass(
                          borderRadius: 24,
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.cyanAccent.withOpacity(0.8),
                                      Colors.blueAccent.withOpacity(0.8),
                                    ],
                                  ),
                                ),
                                child: const Icon(Icons.sports_soccer, color: Colors.black),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Build your league roster',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.format == LeagueFormat.classic
                                          ? 'Add up to $_maxTeamsForFormat teams. We\'ll auto-generate a double round-robin schedule.'
                                          : widget.format == LeagueFormat.uclGroup
                                              ? 'Assign teams into groups (A–H). Fixtures are generated per group.'
                                              : 'Add teams and we\'ll create the first Swiss round for you.',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (widget.format == LeagueFormat.uclGroup) _buildGroupSelector(),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: showTwoPane
                              ? Row(
                                  children: [
                                    Expanded(flex: 3, child: _buildBulkEntry()),
                                    const SizedBox(width: 12),
                                    Expanded(flex: 4, child: _buildPreviewPanel()),
                                  ],
                                )
                              : Column(
                                  children: [
                                    Expanded(flex: 4, child: _buildBulkEntry()),
                                    const SizedBox(height: 12),
                                    Expanded(flex: 6, child: _buildPreviewPanel()),
                                  ],
                                ),
                        ),
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Glass(
        borderRadius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.grid_view, size: 18, color: Colors.cyanAccent),
            const SizedBox(width: 8),
            const Text(
              'Current group',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _groups.map((g) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(g, style: const TextStyle(fontSize: 11)),
                        selected: _selectedGroup == g,
                        selectedColor: Colors.cyanAccent.withOpacity(0.25),
                        backgroundColor: Colors.white10,
                        labelStyle: TextStyle(
                          color: _selectedGroup == g ? Colors.cyanAccent : Colors.white70,
                        ),
                        onSelected: (selected) {
                          if (!selected) return;
                          setState(() => _selectedGroup = g);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBulkEntry() {
    final isShort = MediaQuery.of(context).size.height < 700;

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.cyanAccent.withOpacity(0.18),
                  ),
                  child: const Icon(
                    Icons.format_list_bulleted,
                    color: Colors.cyanAccent,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Step 1 · Enter team names',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Type or paste names, separated by commas or new lines.',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: TextField(
                    controller: _bulkController,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Team A\nTeam B\nTeam C\n\nor\n\nTeam A, Team B, Team C',
                      hintStyle: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_bulkError != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 4, right: 4, bottom: 2),
                child: Text(
                  _bulkError!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _bulkController.clear();
                      _bulkError = null;
                    });
                  },
                  icon: const Icon(Icons.clear_all, size: 16),
                  label: const Text('Clear'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: isShort ? 4 : 8),
                    minimumSize: Size(0, isShort ? 34 : 44),
                    visualDensity: isShort ? VisualDensity.compact : VisualDensity.standard,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _importBulk,
                  style: FilledButton.styleFrom(
                    minimumSize: Size(0, isShort ? 34 : 44),
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: isShort ? 4 : 8),
                    backgroundColor: Colors.white.withOpacity(0.15),
                    visualDensity: isShort ? VisualDensity.compact : VisualDensity.standard,
                  ),
                  icon: const Icon(Icons.playlist_add_check, size: 18),
                  label: const Text('Add to preview'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPanel() {
    final existingCount = _existingTeams.length;
    final newCount = _tempTeams.length;
    final totalCount = existingCount + newCount;

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                Icon(Icons.groups, size: 18, color: Colors.cyanAccent),
                SizedBox(width: 8),
                Text(
                  'Step 2 · Review teams',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _PreviewChip(label: 'Saved: $existingCount', color: Colors.white24),
                const SizedBox(width: 8),
                _PreviewChip(label: 'New: $newCount', color: Colors.cyanAccent.withOpacity(0.24)),
                const Spacer(),
                Text(
                  '$totalCount / $_maxTeamsForFormat',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: existingCount + newCount,
              itemBuilder: (context, i) {
                if (i < existingCount) {
                  final team = _existingTeams[i];
                  final groupLabel = _groupLabelForTeam(team);
                  final label = widget.format == LeagueFormat.uclGroup ? 'Saved · $groupLabel' : 'Saved';
                  return _buildTeamTile(
                    index: i,
                    name: team.name,
                    label: label,
                    isNew: false,
                    onTap: () => _editExistingTeam(i),
                    onRemove: null,
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
                    onTap: null,
                    onRemove: () {
                      setState(() {
                        _tempTeams.removeAt(idx);
                        _bulkError = null;
                      });
                    },
                  );
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: FilledButton.icon(
              onPressed: _generateAndSave,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.auto_mode),
              label: const Text('Save & generate fixtures'),
            ),
          ),
        ],
      ),
    );
  }

  void _editExistingTeam(int index) {
    final team = _existingTeams[index];
    final nameController = TextEditingController(text: team.name);
    String selectedGroup = team.groupId ?? _selectedGroup;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom).add(const EdgeInsets.all(16)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: StatefulBuilder(
                      builder: (ctx, setModalState) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Edit team',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: nameController,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                labelText: 'Team name',
                                labelStyle: TextStyle(color: Colors.white70),
                              ),
                            ),
                            if (widget.format == LeagueFormat.uclGroup) ...[
                              const SizedBox(height: 8),
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Group',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ),
                              DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: selectedGroup,
                                  dropdownColor: const Color(0xFF000428),
                                  style: const TextStyle(color: Colors.cyanAccent),
                                  isExpanded: true,
                                  items: _groups
                                      .map((g) => DropdownMenuItem(
                                            value: g,
                                            child: Text(g),
                                          ))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v == null) return;
                                    setModalState(() => selectedGroup = v);
                                  },
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () {
                                      final newName = nameController.text.trim();
                                      if (newName.isEmpty) return;

                                      setState(() {
                                        _existingTeams[index] = team.copyWith(
                                          name: newName,
                                          groupId: widget.format == LeagueFormat.uclGroup ? selectedGroup : null,
                                          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
                                        );
                                      });

                                      Navigator.of(ctx).pop();
                                    },
                                    child: const Text('Save'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _existingTeams.removeAt(index);
                                  });
                                  Navigator.of(ctx).pop();
                                },
                                icon: const Icon(Icons.delete, color: Colors.redAccent, size: 16),
                                label: const Text('Remove team', style: TextStyle(color: Colors.redAccent)),
                              ),
                            ),
                          ],
                        );
                      },
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

  Widget _buildTeamTile({
    required int index,
    required String name,
    required String label,
    required bool isNew,
    required VoidCallback? onTap,
    required VoidCallback? onRemove,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Glass(
        borderRadius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: isNew ? Colors.cyanAccent.withOpacity(0.18) : Colors.white12,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                if (!isNew && onTap != null)
                  const Icon(
                    Icons.edit,
                    color: Colors.white54,
                    size: 16,
                  ),
                if (isNew && onRemove != null)
                  InkWell(
                    onTap: onRemove,
                    borderRadius: BorderRadius.circular(999),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.close,
                        color: Colors.white54,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  const _PreviewChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
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
    );
  }
}
