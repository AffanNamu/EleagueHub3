import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/fixture_generator.dart';
import '../models/league_format.dart';
import '../models/team.dart';
import 'standings_providers.dart';
import '../widgets/glass_group_card.dart';

class GroupDrawScreen extends ConsumerStatefulWidget {
  final String leagueId;
  const GroupDrawScreen({super.key, required this.leagueId});

  @override
  ConsumerState<GroupDrawScreen> createState() => _GroupDrawScreenState();
}

class _GroupDrawScreenState extends ConsumerState<GroupDrawScreen> {
  final Map<String, List<Team>> groups = {};
  final List<Team> remainingTeams = [];

  List<Team> _allTeams = [];
  bool isDrawing = false;
  bool _isGeneratingFixtures = false;

  // NEW: lock group draw once fixtures exist (critical integrity protection).
  bool _drawLocked = false;

  static const int _groupSize = 4;

  void _toast(String msg, {Color bg = const Color(0xFF101522), Color fg = Colors.white}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        backgroundColor: bg,
        content: Text(msg, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _toastOk(String msg) => _toast(msg, bg: Colors.cyanAccent.withOpacity(0.18), fg: Colors.cyanAccent);
  void _toastWarn(String msg) => _toast(msg, bg: Colors.orangeAccent.withOpacity(0.14), fg: Colors.orangeAccent);
  void _toastErr(String msg) => _toast(msg, bg: Colors.redAccent.withOpacity(0.14), fg: Colors.redAccent);

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_loadLeagueAndTeams);
  }

  List<String> _groupNamesForCount(int teamCount) {
    final groupCount = teamCount ~/ _groupSize;
    const names = <String>[
      'Group A',
      'Group B',
      'Group C',
      'Group D',
      'Group E',
      'Group F',
      'Group G',
      'Group H',
    ];
    return names.take(groupCount).toList();
  }

  Future<void> _loadLeagueAndTeams() async {
    final repo = ref.read(localLeaguesRepositoryProvider);

    final league = await repo.getLeagueById(widget.leagueId);
    final teams = await repo.getTeams(widget.leagueId);
    final matches = await repo.getMatches(widget.leagueId);

    if (!mounted) return;

    _allTeams = teams;

    if (league == null) {
      _toastErr('League not found.');
      return;
    }
    if (league.format != LeagueFormat.uclGroup) {
      _toastErr('This screen is only for UCL Group leagues.');
      return;
    }

    final hasGroupFixtures = matches.any((m) => (m.groupId ?? '').trim().isNotEmpty);
    _drawLocked = hasGroupFixtures;

    if (!(teams.length == 16 || teams.length == 32)) {
      _toastErr('UCL Group supports only 16 or 32 teams. Current: ${teams.length}.');
      setState(() {
        groups.clear();
        remainingTeams.clear();
      });
      return;
    }

    final groupNames = _groupNamesForCount(teams.length);

    groups.clear();
    for (final g in groupNames) {
      groups[g] = <Team>[];
    }

    final assignedIds = <String>{};
    for (final t in teams) {
      final gid = t.groupId?.trim();
      if (gid == null || gid.isEmpty) continue;
      if (!groups.containsKey(gid)) continue;

      if (groups[gid]!.length < _groupSize) {
        groups[gid]!.add(t);
        assignedIds.add(t.id);
      }
    }

    final rem = teams.where((t) => !assignedIds.contains(t.id)).toList()..shuffle(Random());

    setState(() {
      remainingTeams
        ..clear()
        ..addAll(rem);
    });

    if (_drawLocked) {
      _toastWarn('Group draw locked: fixtures already generated.');
    }
  }

  String? _nextGroupWithSpace() {
    for (final entry in groups.entries) {
      if (entry.value.length < _groupSize) return entry.key;
    }
    return null;
  }

  bool get _allGroupsFull =>
      groups.isNotEmpty && groups.values.every((list) => list.length == _groupSize) && remainingTeams.isEmpty;

  Future<void> startDraw() async {
    if (_drawLocked) {
      _toastWarn('Cannot change groups after fixtures are generated.');
      return;
    }
    if (isDrawing) return;
    if (remainingTeams.isEmpty) return;

    setState(() => isDrawing = true);

    while (mounted && remainingTeams.isNotEmpty) {
      final nextGroup = _nextGroupWithSpace();
      if (nextGroup == null) break;

      await Future.delayed(const Duration(milliseconds: 450));
      if (!mounted) break;

      setState(() {
        final team = remainingTeams.removeAt(0);
        groups[nextGroup]!.add(team);

        final idx = _allTeams.indexWhere((t) => t.id == team.id);
        if (idx != -1) {
          _allTeams[idx] = _allTeams[idx].copyWith(groupId: nextGroup);
        }
      });
    }

    try {
      final repo = ref.read(localLeaguesRepositoryProvider);
      await repo.saveTeams(widget.leagueId, _allTeams);
      _toastOk('Groups saved');
    } catch (e) {
      _toastErr('Failed to save groups: $e');
    }

    if (!mounted) return;
    setState(() => isDrawing = false);
  }

  Future<void> _generateGroupFixtures() async {
    if (_drawLocked) {
      _toastWarn('Fixtures already generated.');
      return;
    }
    if (_isGeneratingFixtures) return;

    if (!_allGroupsFull) {
      _toastWarn('Finish the group draw first (all groups must have 4 teams).');
      return;
    }

    setState(() => _isGeneratingFixtures = true);

    try {
      final repo = ref.read(localLeaguesRepositoryProvider);
      final league = await repo.getLeagueById(widget.leagueId);
      if (league == null) {
        _toastErr('League not found.');
        return;
      }

      final existing = await repo.getMatches(widget.leagueId);
      final hasGroupFixtures = existing.any((m) => (m.groupId ?? '').trim().isNotEmpty);
      if (hasGroupFixtures) {
        _toastWarn('Group fixtures already generated.');
        _drawLocked = true;
        return;
      }

      final fixtures = FixtureGenerator.generateUclGroupStage(
        leagueId: widget.leagueId,
        teams: _allTeams,
        doubleRoundRobin: league.settings.doubleRoundRobin,
        groupSize: _groupSize,
      );

      if (fixtures.isEmpty) {
        _toastErr('Failed to generate group fixtures. Check group assignments.');
        return;
      }

      await repo.saveMatches(widget.leagueId, fixtures);
      _toastOk('Group fixtures generated (${fixtures.length} matches).');
      _drawLocked = true;
    } catch (e) {
      _toastErr('Failed to generate fixtures: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingFixtures = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!(_allTeams.length == 16 || _allTeams.length == 32) || groups.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF000428),
        appBar: AppBar(
          title: const Text("UCL Group Draw"),
          backgroundColor: Colors.transparent,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              'UCL Group Draw supports only 16 or 32 teams.\nCurrent teams: ${_allTeams.length}.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }

    final orderedGroupKeys = groups.keys.toList();

    return Scaffold(
      backgroundColor: const Color(0xFF000428),
      appBar: AppBar(
        title: const Text("UCL Group Draw"),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _loadLeagueAndTeams,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_drawLocked)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Group draw is locked because fixtures already exist.',
                style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w800, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_drawLocked || isDrawing) ? null : (remainingTeams.isNotEmpty ? startDraw : null),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white24),
                    child: Text(isDrawing ? "Drawing Teams..." : (remainingTeams.isNotEmpty ? "RESUME DRAW" : "DRAW COMPLETE")),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_drawLocked || !_allGroupsFull || _isGeneratingFixtures) ? null : _generateGroupFixtures,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent.withOpacity(0.22)),
                    icon: _isGeneratingFixtures
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                          )
                        : const Icon(Icons.auto_awesome, color: Colors.cyanAccent),
                    label: const Text(
                      "GENERATE FIXTURES",
                      style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                childAspectRatio: 0.9,
              ),
              itemCount: orderedGroupKeys.length,
              itemBuilder: (context, index) {
                final key = orderedGroupKeys[index];
                final teamNames = groups[key]!.map((t) => t.name).toList();
                return GlassGroupCard(title: key, teams: teamNames);
              },
            ),
          ),
        ],
      ),
    );
  }
}
