import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
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
  final UserProfileRepository _profiles = UserProfileRepository();

  /// Temp entries are uid-driven (internal Firebase uid):
  /// { userId, teamName, group }
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

  /// Cache of fetched profiles for fast preview (keyed by internal Firebase uid).
  final Map<String, String> _teamNameCacheByUserId = {};

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

  Future<void> _loadExistingTeams() async {
    final teams = await _localRepo.getTeams(widget.leagueId);
    if (!mounted) return;
    setState(() {
      _existingTeams = teams;
      _isLoading = false;
    });
  }

  String _groupLabelForTeam(Team t) {
    if (widget.format == LeagueFormat.uclGroup) return t.groupId ?? 'Unassigned';
    return 'League Pool';
  }

  Future<_ResolvedTeam?> _resolveTeamFromUserIdOrShareId(String userIdOrShareId) async {
    final input = userIdOrShareId.trim();
    if (input.isEmpty) return null;

    // If they pasted a real uid and we already cached the team name, skip network.
    final cached = _teamNameCacheByUserId[input];
    if (cached != null && cached.trim().isNotEmpty) {
      return _ResolvedTeam(userId: input, teamName: cached.trim());
    }

    final profile = await _profiles.fetchByUserIdOrShareId(input);
    if (profile == null) return null;

    final resolvedUserId = profile.userId.trim();
    final teamName = profile.teamName.trim();
    if (resolvedUserId.isEmpty || teamName.isEmpty) return null;

    _teamNameCacheByUserId[resolvedUserId] = teamName;
    return _ResolvedTeam(userId: resolvedUserId, teamName: teamName);
  }

  Future<void> _addResolvedTeam(_ResolvedTeam resolved) async {
    final totalCurrent = _existingTeams.length + _tempTeams.length;
    if (totalCurrent >= _maxTeamsForFormat) {
      if (!mounted) return;
      setState(() => _bulkError = 'Maximum $_maxTeamsForFormat teams allowed for this format.');
      return;
    }

    final alreadyInPreview = _tempTeams.any((t) => (t['userId'] ?? '') == resolved.userId);
    if (alreadyInPreview) return;

    final alreadySaved = _existingTeams.any((t) => t.id == resolved.userId);
    if (alreadySaved) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This user is already added to this league.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _bulkError = null;
      _tempTeams.add({
        // IMPORTANT: Always store internal Firebase uid (not the short share id).
        'userId': resolved.userId,
        'teamName': resolved.teamName,
        'group': widget.format == LeagueFormat.uclGroup ? _selectedGroup : 'League Pool',
      });

      // Optional convenience: auto-advance group assignment when adding.
      if (widget.format == LeagueFormat.uclGroup) {
        final next = (_groups.indexOf(_selectedGroup) + 1) % _groups.length;
        _selectedGroup = _groups[next];
      }
    });
  }

  Future<void> _showAddSingleDialog() async {
    final controller = TextEditingController();
    Timer? debounce;

    bool resolving = false;
    _ResolvedTeam? resolved;
    String? error;

    Future<void> resolveNow(StateSetter setModalState) async {
      final raw = controller.text.trim();
      if (raw.isEmpty) {
        setModalState(() {
          resolved = null;
          error = null;
          resolving = false;
        });
        return;
      }

      setModalState(() {
        resolving = true;
        error = null;
      });

      try {
        final r = await _resolveTeamFromUserIdOrShareId(raw);
        if (!mounted) return;

        if (r == null) {
          setModalState(() {
            resolved = null;
            resolving = false;
            error = 'No profile found for this UserId. Ask the player to login once and share their UserId (eSxxxxxx).';
          });
          return;
        }

        setModalState(() {
          resolved = r;
          resolving = false;
          error = null;
        });
      } catch (e) {
        if (!mounted) return;
        setModalState(() {
          resolved = null;
          resolving = false;
          error = 'Lookup failed: $e';
        });
      }
    }

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0A1D37),
            title: const Text(
              'Add player by UserId',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: StatefulBuilder(
              builder: (ctx, setModalState) {
                return SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: controller,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'eS44e35f  (or Firebase uid)',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(Icons.badge, color: Colors.white70),
                          suffixIcon: resolving
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                                  ),
                                )
                              : IconButton(
                                  tooltip: 'Lookup',
                                  onPressed: () => resolveNow(setModalState),
                                  icon: const Icon(Icons.search, color: Colors.cyanAccent),
                                ),
                        ),
                        onChanged: (_) {
                          debounce?.cancel();
                          debounce = Timer(const Duration(milliseconds: 350), () {
                            if (!ctx.mounted) return;
                            resolveNow(setModalState);
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Glass(
                        borderRadius: 16,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: Colors.white70, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  widget.format == LeagueFormat.uclGroup
                                      ? 'Tip: Use the short UserId (starts with eS). Group assignment rotates automatically.'
                                      : 'Tip: Use the short UserId (starts with eS). Team name is loaded automatically.',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.25),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (resolved != null)
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.cyanAccent.withOpacity(0.25)),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Resolved profile',
                                style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w900, fontSize: 12),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                resolved!.teamName,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'uid: ${resolved!.userId}',
                                style: const TextStyle(color: Colors.white54, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.format == LeagueFormat.uclGroup) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.grid_view, size: 16, color: Colors.white60),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Will be placed in: $_selectedGroup',
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          error!,
                          style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
              ),
              FilledButton.icon(
                onPressed: () async {
                  if (resolved == null) return;
                  await _addResolvedTeam(resolved!);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                icon: const Icon(Icons.person_add),
                label: const Text('Add'),
              ),
            ],
          );
        },
      );
    } finally {
      debounce?.cancel();
      controller.dispose();
    }
  }

  Future<void> _showPasteListSheet() async {
    final controller = TextEditingController();

    bool validating = false;
    String? error;

    List<_BulkRow> rows = [];

    List<String> parseLines(String raw) {
      return raw
          .split(RegExp(r'[,\n]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    Future<void> validateNow(StateSetter setModalState) async {
      final inputs = parseLines(controller.text);
      if (inputs.isEmpty) {
        setModalState(() {
          rows = [];
          error = 'Paste at least one UserId.';
        });
        return;
      }

      setModalState(() {
        validating = true;
        error = null;
        rows = inputs.map((i) => _BulkRow(input: i, resolved: null, status: _BulkStatus.pending)).toList();
      });

      try {
        final futures = inputs.map((input) async {
          final r = await _resolveTeamFromUserIdOrShareId(input);
          return MapEntry(input, r);
        }).toList();

        final results = await Future.wait(futures);

        if (!mounted) return;

        final updated = <_BulkRow>[];
        for (final entry in results) {
          final r = entry.value;
          if (r == null) {
            updated.add(_BulkRow(input: entry.key, resolved: null, status: _BulkStatus.notFound));
          } else {
            updated.add(_BulkRow(input: entry.key, resolved: r, status: _BulkStatus.ok));
          }
        }

        setModalState(() {
          rows = updated;
          validating = false;
          error = null;
        });
      } catch (e) {
        if (!mounted) return;
        setModalState(() {
          validating = false;
          error = 'Validation failed: $e';
        });
      }
    }

    Future<void> addValidAndClose(BuildContext ctx) async {
      final valid = rows.where((r) => r.status == _BulkStatus.ok && r.resolved != null).map((r) => r.resolved!).toList();
      if (valid.isEmpty) return;

      for (final r in valid) {
        await _addResolvedTeam(r);
      }
      if (ctx.mounted) Navigator.of(ctx).pop();
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset).add(const EdgeInsets.all(12)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Glass(
                  borderRadius: 28,
                  child: StatefulBuilder(
                    builder: (ctx, setModalState) {
                      final okCount = rows.where((r) => r.status == _BulkStatus.ok).length;
                      final notFoundCount = rows.where((r) => r.status == _BulkStatus.notFound).length;

                      return Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Paste UserIds',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Paste one per line (or comma-separated). Use short UserId (eSxxxxxx) or Firebase uid.',
                              style: TextStyle(color: Colors.white70, fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.25),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: TextField(
                                    controller: controller,
                                    maxLines: 6,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: const InputDecoration(
                                      hintText: 'eS44e35f\neS91a2b3\nuid_3',
                                      hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: validating
                                        ? null
                                        : () {
                                            setModalState(() {
                                              controller.clear();
                                              rows = [];
                                              error = null;
                                            });
                                          },
                                    icon: const Icon(Icons.clear_all, size: 18),
                                    label: const Text('Clear'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white70,
                                      side: const BorderSide(color: Colors.white24),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: validating ? null : () => validateNow(setModalState),
                                    icon: validating
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.verified),
                                    label: const Text('Validate'),
                                  ),
                                ),
                              ],
                            ),
                            if (rows.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _MiniChip(label: 'OK: $okCount', color: Colors.cyanAccent.withOpacity(0.22)),
                                  const SizedBox(width: 8),
                                  _MiniChip(label: 'Not found: $notFoundCount', color: Colors.redAccent.withOpacity(0.18)),
                                  const Spacer(),
                                  Text(
                                    '${_existingTeams.length + _tempTeams.length} / $_maxTeamsForFormat',
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 260),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: rows.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                                  itemBuilder: (context, index) {
                                    final r = rows[index];
                                    final isOk = r.status == _BulkStatus.ok && r.resolved != null;

                                    return Glass(
                                      borderRadius: 16,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor: isOk
                                                  ? Colors.cyanAccent.withOpacity(0.18)
                                                  : Colors.white.withOpacity(0.08),
                                              child: Icon(
                                                isOk ? Icons.check : Icons.close,
                                                size: 16,
                                                color: isOk ? Colors.cyanAccent : Colors.white54,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    r.input,
                                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    isOk ? r.resolved!.teamName : 'No profile found',
                                                    style: TextStyle(
                                                      color: isOk ? Colors.white70 : Colors.white38,
                                                      fontSize: 11,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                            if (error != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                error!,
                                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    child: const Text('Close', style: TextStyle(color: Colors.white70)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: validating ? null : () => addValidAndClose(ctx),
                                    icon: const Icon(Icons.playlist_add_check),
                                    label: Text('Add valid${rows.isEmpty ? '' : ' ($okCount)'}'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    controller.dispose();
  }

  Future<void> _generateAndSave() async {
    if (_tempTeams.isEmpty && _existingTeams.isEmpty) {
      if (mounted) context.go('/leagues/${widget.leagueId}');
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    // Teams are created from userId => teamName (profile), so admin never types team names.
    final newTeams = _tempTeams.map<Team>((t) {
      final groupName = t['group']!;
      final String? groupId = widget.format == LeagueFormat.uclGroup ? groupName : null;

      final userId = t['userId']!;
      final teamName = t['teamName']!;

      return Team(
        id: userId,
        leagueId: widget.leagueId,
        name: teamName,
        groupId: groupId,
        updatedAtMs: now,
        version: 1,
      );
    }).toList();

    final allTeams = <Team>[..._existingTeams, ...newTeams];

    await _localRepo.saveTeams(widget.leagueId, allTeams);

    // Link membership.teamId to the team (teamId == userId) so "My Matches" can work silently.
    for (final t in newTeams) {
      await _localRepo.assignTeamToUserInLeague(
        leagueId: widget.leagueId,
        userId: t.id,
        teamId: t.id,
      );
    }

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
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Glass(
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
                                      'Add players (by UserId)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.format == LeagueFormat.uclGroup
                                          ? 'Use the short UserId (starts with eS). We will auto-load the team name from the user profile and place teams into groups.'
                                          : 'Use the short UserId (starts with eS). We will auto-load the team name from the user profile.',
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.format == LeagueFormat.uclGroup) ...[
                          const SizedBox(height: 10),
                          _buildGroupSelector(),
                        ],
                        const SizedBox(height: 12),
                        Expanded(
                          child: showTwoPane
                              ? Row(
                                  children: [
                                    Expanded(flex: 3, child: _buildAddPanel()),
                                    const SizedBox(width: 12),
                                    Expanded(flex: 4, child: _buildPreviewPanel()),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _buildAddPanel(),
                                    const SizedBox(height: 12),
                                    Expanded(child: _buildPreviewPanel()),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddPanel() {
    final existingCount = _existingTeams.length;
    final newCount = _tempTeams.length;
    final totalCount = existingCount + newCount;

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                Icon(Icons.person_add_alt_1, size: 18, color: Colors.cyanAccent),
                SizedBox(width: 8),
                Text(
                  'Add players',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _MiniChip(label: 'Saved: $existingCount', color: Colors.white24),
                const SizedBox(width: 8),
                _MiniChip(label: 'New: $newCount', color: Colors.cyanAccent.withOpacity(0.24)),
                const Spacer(),
                Text(
                  '$totalCount / $_maxTeamsForFormat',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          if (_bulkError != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _bulkError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _showAddSingleDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Add one player'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showPasteListSheet,
              icon: const Icon(Icons.playlist_add),
              label: const Text('Paste a list'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Glass(
            borderRadius: 18,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, size: 18, color: Colors.white70),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Admin enters only UserId. Team name is loaded from the user profile automatically.',
                      style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 11, height: 1.25),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSelector() {
    return Glass(
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
                  'Review teams',
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
                _MiniChip(label: 'Saved: $existingCount', color: Colors.white24),
                const SizedBox(width: 8),
                _MiniChip(label: 'New: $newCount', color: Colors.cyanAccent.withOpacity(0.24)),
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
            child: (existingCount + newCount) == 0
                ? Center(
                    child: Text(
                      'No teams yet.\nTap “Add one player” or “Paste a list”.',
                      style: TextStyle(color: Colors.white.withOpacity(0.55), height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
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
                          name: team['teamName']!,
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
                              'Team details',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Team name',
                                style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                team.name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'uid (internal)',
                                style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                team.id,
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ),
                            if (widget.format == LeagueFormat.uclGroup) ...[
                              const SizedBox(height: 10),
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
                                  items: _groups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
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
                                    child: const Text('Close', style: TextStyle(color: Colors.white70)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () {
                                      setState(() {
                                        _existingTeams[index] = team.copyWith(
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

class _ResolvedTeam {
  final String userId; // internal Firebase uid
  final String teamName;

  const _ResolvedTeam({
    required this.userId,
    required this.teamName,
  });
}

enum _BulkStatus { pending, ok, notFound }

class _BulkRow {
  final String input;
  final _ResolvedTeam? resolved;
  final _BulkStatus status;

  const _BulkRow({
    required this.input,
    required this.resolved,
    required this.status,
  });
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
