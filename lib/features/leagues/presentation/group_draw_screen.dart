import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../logic/fixture_generator.dart';
import '../models/fixture_match.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../models/team.dart';
import '../widgets/glass_group_card.dart';
import 'standings_providers.dart';

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

  bool _loading = true;
  String? _loadError;

  bool _drawLocked = false;

  static const int _groupSize = 4;

  Color _baseToastBg(ThemeData theme) {
    return theme.brightness == Brightness.dark ? const Color(0xFF101522) : const Color(0xFF0F172A);
  }

  void _toast(String msg, {Color? bg, Color? fg}) {
    if (!mounted) return;

    final theme = Theme.of(context);
    final resolvedBg = bg ?? _baseToastBg(theme);
    final resolvedFg = fg ?? Colors.white;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        backgroundColor: resolvedBg,
        content: Text(msg, style: TextStyle(color: resolvedFg, fontWeight: FontWeight.w600)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _toastOk(String msg) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final baseBg = _baseToastBg(theme);
    final accent = cs.primary;
    _toast(msg, bg: Color.alphaBlend(accent.withOpacity(0.22), baseBg), fg: accent);
  }

  void _toastWarn(String msg) {
    const warn = Color(0xFFF59E0B);
    final theme = Theme.of(context);
    final baseBg = _baseToastBg(theme);
    _toast(msg, bg: Color.alphaBlend(warn.withOpacity(0.22), baseBg), fg: warn);
  }

  void _toastErr(String msg) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final baseBg = _baseToastBg(theme);
    _toast(msg, bg: Color.alphaBlend(cs.error.withOpacity(0.22), baseBg), fg: cs.error);
  }

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

  String _displayGroupName(String groupId) {
    final l10n = context.l10n;
    switch (groupId) {
      case 'Group A':
        return l10n.tr('add_teams_group_a');
      case 'Group B':
        return l10n.tr('add_teams_group_b');
      case 'Group C':
        return l10n.tr('add_teams_group_c');
      case 'Group D':
        return l10n.tr('add_teams_group_d');
      case 'Group E':
        return l10n.tr('add_teams_group_e');
      case 'Group F':
        return l10n.tr('add_teams_group_f');
      case 'Group G':
        return l10n.tr('add_teams_group_g');
      case 'Group H':
        return l10n.tr('add_teams_group_h');
      default:
        return groupId;
    }
  }

  Future<void> _loadLeagueAndTeams() async {
    final l10n = context.l10n;

    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final repo = ref.read(localLeaguesRepositoryProvider);

      final League? league = await repo.getLeagueById(widget.leagueId).timeout(const Duration(seconds: 20));
      final List<Team> teams = await repo.getTeams(widget.leagueId).timeout(const Duration(seconds: 25));
      final List<FixtureMatch> matches = await repo.getMatches(widget.leagueId).timeout(const Duration(seconds: 25));

      if (!mounted) return;

      _allTeams = teams;

      if (league == null) {
        setState(() {
          _loadError = l10n.tr('fixtures_league_not_found');
          _loading = false;
        });
        return;
      }
      if (league.format != LeagueFormat.uclGroup) {
        setState(() {
          _loadError = l10n.tr('group_draw_only_ucl_group');
          _loading = false;
        });
        return;
      }

      _drawLocked = matches.any((m) => (m.groupId ?? '').trim().isNotEmpty);

      if (!(teams.length == 16 || teams.length == 32)) {
        _toastErr('${l10n.tr('admin_score_group_team_count_error_prefix')}${teams.length}.');
        setState(() {
          groups.clear();
          remainingTeams.clear();
          _loading = false;
        });
        return;
      }

      final groupNames = _groupNamesForCount(teams.length);

      groups
        ..clear()
        ..addEntries(groupNames.map((g) => MapEntry(g, <Team>[])));

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
        _loading = false;
      });

      if (_drawLocked) {
        _toastWarn(l10n.tr('group_draw_locked_toast'));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = UserFriendlyError.toMessage(e);
        _loading = false;
      });
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
    final l10n = context.l10n;

    if (_drawLocked) {
      _toastWarn(l10n.tr('group_draw_cannot_change_after_fixtures'));
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
      await repo.saveTeams(widget.leagueId, _allTeams).timeout(const Duration(seconds: 25));
      _toastOk(l10n.tr('group_draw_groups_saved_toast'));
    } catch (e) {
      _toastErr(UserFriendlyError.toMessage(e));
    }

    if (!mounted) return;
    setState(() => isDrawing = false);
  }

  Future<void> _generateGroupFixtures() async {
    final l10n = context.l10n;

    if (_drawLocked) {
      _toastWarn(l10n.tr('admin_score_group_fixtures_already_exist'));
      return;
    }
    if (_isGeneratingFixtures) return;

    if (!_allGroupsFull) {
      _toastWarn(l10n.tr('admin_score_complete_group_draw_first'));
      return;
    }

    setState(() => _isGeneratingFixtures = true);

    try {
      final repo = ref.read(localLeaguesRepositoryProvider);

      final League? league = await repo.getLeagueById(widget.leagueId).timeout(const Duration(seconds: 20));
      if (league == null) {
        _toastErr(l10n.tr('fixtures_league_not_found'));
        return;
      }

      final existing = await repo.getMatches(widget.leagueId).timeout(const Duration(seconds: 25));
      final hasGroupFixtures = existing.any((m) => (m.groupId ?? '').trim().isNotEmpty);
      if (hasGroupFixtures) {
        _toastWarn(l10n.tr('admin_score_group_fixtures_already_exist'));
        if (mounted) setState(() => _drawLocked = true);
        return;
      }

      final fixtures = FixtureGenerator.generateUclGroupStage(
        leagueId: widget.leagueId,
        teams: _allTeams,
        doubleRoundRobin: league.settings.doubleRoundRobin,
        groupSize: _groupSize,
      );

      if (fixtures.isEmpty) {
        _toastErr(l10n.tr('group_draw_failed_generate_group_fixtures_check_groups'));
        return;
      }

      await repo.saveMatches(widget.leagueId, fixtures).timeout(const Duration(seconds: 25));
      _toastOk(
        '${l10n.tr('admin_score_group_fixtures_generated_prefix')}${fixtures.length}${l10n.tr('admin_score_fixtures_generated_suffix')}',
      );
      if (mounted) setState(() => _drawLocked = true);
    } catch (e) {
      _toastErr(UserFriendlyError.toMessage(e));
    } finally {
      if (mounted) setState(() => _isGeneratingFixtures = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return GlassScaffold(
        appBar: AppBar(
          title: Text(l10n.tr('group_draw_appbar_title')),
          backgroundColor: Colors.transparent,
        ),
        body: SafeArea(
          child: Center(child: CircularProgressIndicator(color: cs.primary)),
        ),
      );
    }

    if (_loadError != null) {
      return GlassScaffold(
        appBar: AppBar(
          title: Text(l10n.tr('group_draw_appbar_title')),
          backgroundColor: Colors.transparent,
          actions: [
            IconButton(
              tooltip: l10n.tr('admin_knockout_reload_tooltip'),
              onPressed: _loadLeagueAndTeams,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Glass(
                borderRadius: 20,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _loadError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.error, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _loadLeagueAndTeams,
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.tr('common_retry')),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => Navigator.maybePop(context),
                      child: Text(l10n.tr('common_back')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (!(_allTeams.length == 16 || _allTeams.length == 32) || groups.isEmpty) {
      return GlassScaffold(
        appBar: AppBar(
          title: Text(l10n.tr('group_draw_appbar_title')),
          backgroundColor: Colors.transparent,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              '${l10n.tr('group_draw_team_count_help_prefix')}${_allTeams.length}.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onBackground.withOpacity(0.72),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    final orderedGroupKeys = groups.keys.toList();

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('group_draw_appbar_title')),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: l10n.tr('admin_knockout_reload_tooltip'),
            onPressed: _loadLeagueAndTeams,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_drawLocked)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
              child: Text(
                l10n.tr('group_draw_locked_banner'),
                style: const TextStyle(
                  color: Color(0xFFF59E0B),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: (_drawLocked || isDrawing) ? null : (remainingTeams.isNotEmpty ? startDraw : null),
                    child: Text(
                      isDrawing
                          ? l10n.tr('group_draw_drawing_teams')
                          : (remainingTeams.isNotEmpty ? l10n.tr('group_draw_resume_draw') : l10n.tr('group_draw_draw_complete')),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_drawLocked || !_allGroupsFull || _isGeneratingFixtures) ? null : _generateGroupFixtures,
                    icon: _isGeneratingFixtures
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      l10n.tr('group_draw_generate_fixtures').toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.4),
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
                return GlassGroupCard(title: _displayGroupName(key), teams: teamNames);
              },
            ),
          ),
        ],
      ),
    );
  }
}
