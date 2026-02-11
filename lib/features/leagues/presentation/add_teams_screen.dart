import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../data/leagues_repository_local.dart';
import '../domain/algorithms/swiss_pairing.dart';
import '../logic/fixture_generator.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../models/membership.dart';
import '../models/team.dart';
import 'widgets/roster_csv_importer.dart';

/// Add teams screen (admin/organizer tool)
///
/// ID POLICY (IMPORTANT):
/// - Internal IDs stored in Team.id / Membership.userId / Membership.teamId MUST be Firebase Auth UID.
/// - shareId (short id) is allowed ONLY for display + user input.
/// - Input shareId is resolved to Firebase UID via UserProfileRepository.fetchByUserIdOrShareId.
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
  static const String _leaguePoolGroup = 'League Pool';
  static const String _unassignedGroup = 'Unassigned';

  late LocalLeaguesRepository _localRepo;
  final UserProfileRepository _profiles = UserProfileRepository();

  League? _league;

  /// Temp entries are uid-driven (Firebase uid):
  /// { userId, teamName, group }
  final List<Map<String, String>> _tempTeams = [];

  List<Team> _existingTeams = [];
  bool _isLoading = true;

  bool get _isGroupLeague => widget.format == LeagueFormat.uclGroup;

  String _selectedGroup = 'Group A';

  final List<String> _groupsAll = const [
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

  final Map<String, String> _teamNameCacheByUserId = {};

  int get _savedCount => _existingTeams.length;
  int get _newCount => _tempTeams.length;
  int get _totalCount => _savedCount + _newCount;

  int get _maxTeamsForFormat {
    switch (widget.format) {
      case LeagueFormat.classic:
        return (_league?.maxTeams ?? 20).clamp(2, 40);
      case LeagueFormat.uclGroup:
        return 32;
      case LeagueFormat.uclSwiss:
        return 36;
    }
  }

  bool get _requiredCountReached {
    final n = _totalCount;
    switch (widget.format) {
      case LeagueFormat.uclGroup:
        return n == 16 || n == 32;
      case LeagueFormat.uclSwiss:
        return n == 18 || n == 36;
      case LeagueFormat.classic:
      default:
        return n >= 2;
    }
  }

  String _shareId(String uid) {
    final u = uid.trim();
    if (u.isEmpty) return '';
    // Safe deterministic fallback even if /users doc missing.
    return UserProfile.deriveShareIdFromUid(u);
  }

  /// Group UI list:
  /// - If any existing/new team already uses groups E–H, show all groups.
  /// - Else: show A–D until totalCount > 16, then show A–H.
  List<String> get _activeGroups {
    if (!_isGroupLeague) return const <String>[];

    final used = <String>{
      for (final t in _existingTeams) (t.groupId ?? '').trim(),
      for (final t in _tempTeams) (t['group'] ?? '').trim(),
    };
    used.removeWhere((e) => e.isEmpty);

    final usesExtended = used.any((g) => g == 'Group E' || g == 'Group F' || g == 'Group G' || g == 'Group H');
    if (usesExtended) return _groupsAll;

    return (_totalCount > 16) ? _groupsAll : _groupsAll.take(4).toList();
  }

  @override
  void initState() {
    super.initState();
    _localRepo = LocalLeaguesRepository(ref.read(prefsServiceProvider));
    _loadExistingTeams();
  }

  Color _baseSnackBg(ThemeData theme) {
    // Use a premium dark overlay even in light mode (keeps contrast & consistency).
    return theme.brightness == Brightness.dark ? const Color(0xFF101522) : const Color(0xFF0F172A);
  }

  void _snack(String msg, {Color? bg, Color? fg}) {
    if (!mounted) return;

    final theme = Theme.of(context);
    final resolvedBg = bg ?? _baseSnackBg(theme);
    final resolvedFg = fg ?? Colors.white;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        backgroundColor: resolvedBg,
        content: Text(
          msg,
          style: TextStyle(color: resolvedFg, fontWeight: FontWeight.w600),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _snackOk(String msg) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final baseBg = _baseSnackBg(theme);
    _snack(msg, bg: Color.alphaBlend(accent.withOpacity(0.22), baseBg), fg: accent);
  }

  void _snackWarn(String msg) {
    const warn = Color(0xFFF59E0B); // premium amber
    final theme = Theme.of(context);
    final baseBg = _baseSnackBg(theme);
    _snack(msg, bg: Color.alphaBlend(warn.withOpacity(0.22), baseBg), fg: warn);
  }

  void _snackErr(String msg) {
    final theme = Theme.of(context);
    final err = theme.colorScheme.error;
    final baseBg = _baseSnackBg(theme);
    _snack(msg, bg: Color.alphaBlend(err.withOpacity(0.22), baseBg), fg: err);
  }

  Future<void> _loadExistingTeams() async {
    final league = await _localRepo.getLeagueById(widget.leagueId);
    final teams = await _localRepo.getTeams(widget.leagueId);

    // Auto-show joined participants (memberships) in this screen too.
    final allMemberships = await _localRepo.listMemberships();
    final memberUserIds = allMemberships
        .where((m) => m.leagueId == widget.leagueId && m.role == LeagueRole.member)
        .map((m) => m.userId.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final existingIds = teams.map((t) => t.id).toSet();
    final tempIds = _tempTeams.map((t) => (t['userId'] ?? '').trim()).where((id) => id.isNotEmpty).toSet();

    final autoTemp = <Map<String, String>>[];
    final defaultGroup = _isGroupLeague ? _selectedGroup : _leaguePoolGroup;

    for (final uid in memberUserIds) {
      if (existingIds.contains(uid)) continue;
      if (tempIds.contains(uid)) continue;

      String name = (_teamNameCacheByUserId[uid] ?? '').trim();
      if (name.isEmpty) {
        try {
          final p = await _profiles.fetchByUserId(uid);
          final resolved = (p?.teamName ?? '').trim();
          if (resolved.isNotEmpty) {
            name = resolved;
            _teamNameCacheByUserId[uid] = resolved;
          }
        } catch (_) {
          // Offline / permission / transient error: ignore and fallback.
        }
      }

      // UI-friendly fallback: show short id instead of raw UID.
      if (name.isEmpty) name = _shareId(uid);

      autoTemp.add({
        'userId': uid, // internal uid
        'teamName': name,
        'group': defaultGroup,
      });
    }

    if (!mounted) return;

    setState(() {
      _league = league;
      _existingTeams = teams;
      _tempTeams.addAll(autoTemp);
      _isLoading = false;

      if (_isGroupLeague) {
        final active = _activeGroups;
        if (!active.contains(_selectedGroup)) {
          _selectedGroup = active.isNotEmpty ? active.first : 'Group A';
        }
      }
    });
  }

  String _formatLabel(AppLocalizations l10n) {
    switch (widget.format) {
      case LeagueFormat.classic:
        return l10n.tr('add_teams_format_classic');
      case LeagueFormat.uclGroup:
        return l10n.tr('add_teams_format_ucl_group');
      case LeagueFormat.uclSwiss:
        return l10n.tr('add_teams_format_ucl_swiss');
    }
  }

  String _unlockHint(AppLocalizations l10n) {
    switch (widget.format) {
      case LeagueFormat.uclGroup:
        return l10n.tr('add_teams_unlock_group');
      case LeagueFormat.uclSwiss:
        return l10n.tr('add_teams_unlock_swiss');
      case LeagueFormat.classic:
      default:
        return l10n.tr('add_teams_unlock_classic');
    }
  }

  String _groupDisplayName(AppLocalizations l10n, String groupId) {
    final g = groupId.trim();
    if (g == _leaguePoolGroup) return l10n.tr('add_teams_league_pool');
    if (g == _unassignedGroup) return l10n.tr('add_teams_unassigned');

    if (g == 'Group A') return l10n.tr('add_teams_group_a');
    if (g == 'Group B') return l10n.tr('add_teams_group_b');
    if (g == 'Group C') return l10n.tr('add_teams_group_c');
    if (g == 'Group D') return l10n.tr('add_teams_group_d');
    if (g == 'Group E') return l10n.tr('add_teams_group_e');
    if (g == 'Group F') return l10n.tr('add_teams_group_f');
    if (g == 'Group G') return l10n.tr('add_teams_group_g');
    if (g == 'Group H') return l10n.tr('add_teams_group_h');

    return g;
  }

  String _groupLabelForTeam(Team t) {
    final l10n = context.l10n;
    if (_isGroupLeague) return _groupDisplayName(l10n, t.groupId ?? _unassignedGroup);
    return l10n.tr('add_teams_league_pool');
  }

  Future<_ResolvedTeam?> _resolveTeamFromUserIdOrShareId(String userIdOrShareId) async {
    final input = userIdOrShareId.trim();
    if (input.isEmpty) return null;

    // Cache is keyed by internal uid. If the user pasted a uid, cache can hit.
    final cached = _teamNameCacheByUserId[input];
    if (cached != null && cached.trim().isNotEmpty) {
      return _ResolvedTeam(userId: input, teamName: cached.trim());
    }

    final profile = await _profiles.fetchByUserIdOrShareId(input);
    if (profile == null) return null;

    // Canonical internal id:
    final resolvedUserId = profile.userId.trim(); // Firebase UID
    final teamName = profile.teamName.trim();
    if (resolvedUserId.isEmpty || teamName.isEmpty) return null;

    _teamNameCacheByUserId[resolvedUserId] = teamName;
    return _ResolvedTeam(userId: resolvedUserId, teamName: teamName);
  }

  Future<void> _addResolvedTeam(
    _ResolvedTeam resolved, {
    String? groupOverride,
  }) async {
    final l10n = context.l10n;

    final totalCurrent = _existingTeams.length + _tempTeams.length;
    if (totalCurrent >= _maxTeamsForFormat) {
      if (!mounted) return;
      setState(() => _bulkError =
          '${l10n.tr('add_teams_max_teams_error_prefix')} $_maxTeamsForFormat ${l10n.tr('add_teams_max_teams_error_suffix')}');
      return;
    }

    final alreadyInPreview = _tempTeams.any((t) => (t['userId'] ?? '') == resolved.userId);
    if (alreadyInPreview) return;

    final alreadySaved = _existingTeams.any((t) => t.id == resolved.userId);
    if (alreadySaved) {
      _snackWarn(l10n.tr('add_teams_user_already_added'));
      return;
    }

    final String groupToUse;
    if (_isGroupLeague) {
      final active = _activeGroups;
      final desired = (groupOverride != null && groupOverride.trim().isNotEmpty) ? groupOverride.trim() : _selectedGroup;
      groupToUse = active.contains(desired) ? desired : (active.isNotEmpty ? active.first : 'Group A');
    } else {
      groupToUse = _leaguePoolGroup;
    }

    if (!mounted) return;
    setState(() {
      _bulkError = null;
      _tempTeams.add({
        'userId': resolved.userId, // internal uid
        'teamName': resolved.teamName,
        'group': groupToUse,
      });

      if (_isGroupLeague && (groupOverride == null || groupOverride.trim().isEmpty)) {
        final active = _activeGroups;
        if (active.isNotEmpty) {
          final next = (active.indexOf(_selectedGroup) + 1) % active.length;
          _selectedGroup = active[next];
        }
      }
    });
  }

  Future<void> _importRosterFromCsv() async {
    await showRosterCsvImportFlow(
      context: context,
      isGroupLeague: _isGroupLeague,
      allowedGroups: _activeGroups,
      resolveProfile: (userIdOrShareId) async {
        final r = await _resolveTeamFromUserIdOrShareId(userIdOrShareId);
        if (r == null) return null;
        return ResolvedRosterProfile(userId: r.userId, teamName: r.teamName);
      },
      onAddResolved: (resolved, {groupOverride}) async {
        await _addResolvedTeam(
          _ResolvedTeam(userId: resolved.userId, teamName: resolved.teamName),
          groupOverride: groupOverride,
        );
      },
      currentTeamCount: _existingTeams.length + _tempTeams.length,
      maxTeams: _maxTeamsForFormat,
    );
  }

  Future<void> _showAddSingleDialog() async {
    final l10n = context.l10n;

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
            error = l10n.tr('add_teams_no_profile_found_help');
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
          error = '${l10n.tr('add_teams_lookup_failed_prefix')} $e';
        });
      }
    }

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          final cs = theme.colorScheme;
          final onSurface = cs.onSurface;
          final primary = cs.primary;

          return AlertDialog(
            backgroundColor: cs.surface,
            title: Text(
              l10n.tr('add_teams_add_player_by_userid_title'),
              style: TextStyle(color: onSurface, fontWeight: FontWeight.bold),
            ),
            content: StatefulBuilder(
              builder: (ctx, setModalState) {
                final resolvedShare = (resolved == null) ? '' : _shareId(resolved!.userId);

                return SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: l10n.tr('add_teams_userid_hint'),
                          prefixIcon: const Icon(Icons.badge),
                          suffixIcon: resolving
                              ? Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: primary),
                                  ),
                                )
                              : IconButton(
                                  tooltip: l10n.tr('add_teams_lookup_tooltip'),
                                  onPressed: () => resolveNow(setModalState),
                                  icon: Icon(Icons.search, color: primary),
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
                      if (resolved != null)
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: primary.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: primary.withOpacity(0.22)),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.tr('add_teams_resolved_profile_title'),
                                style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                resolved!.teamName,
                                style: TextStyle(
                                  color: onSurface,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                // UI: show shareId prominently
                                '${l10n.tr('add_teams_uid_prefix')}$resolvedShare',
                                style: TextStyle(
                                  color: onSurface.withOpacity(0.65),
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                // Debug: internal uid (helps support)
                                'Internal uid: ${resolved!.userId}',
                                style: TextStyle(
                                  color: onSurface.withOpacity(0.45),
                                  fontSize: 10,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_isGroupLeague) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.grid_view, size: 16, color: onSurface.withOpacity(0.60)),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${l10n.tr('add_teams_will_be_placed_in_prefix')}${_groupDisplayName(l10n, _selectedGroup)}',
                                      style: TextStyle(color: onSurface.withOpacity(0.72), fontSize: 12),
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
                          style: TextStyle(
                            color: cs.error,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
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
                child: Text(l10n.tr('common_cancel')),
              ),
              FilledButton.icon(
                onPressed: () async {
                  if (resolved == null) return;
                  await _addResolvedTeam(resolved!);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                icon: const Icon(Icons.person_add),
                label: Text(l10n.tr('common_add')),
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
    final l10n = context.l10n;

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
          error = l10n.tr('add_teams_paste_at_least_one_userid');
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
          error = '${l10n.tr('add_teams_validation_failed_prefix')} $e';
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
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final onSurface = cs.onSurface;
        final primary = cs.primary;

        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

        final inputBg = theme.brightness == Brightness.dark ? Colors.black.withOpacity(0.20) : Colors.black.withOpacity(0.04);
        final inputStroke = theme.brightness == Brightness.dark ? Colors.white.withOpacity(0.18) : onSurface.withOpacity(0.14);

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
                            Text(
                              l10n.tr('add_teams_paste_userids_title'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.tr('add_teams_paste_userids_subtitle'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: onSurface.withOpacity(0.70),
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: inputBg,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: inputStroke),
                                  ),
                                  child: TextField(
                                    controller: controller,
                                    maxLines: 6,
                                    style: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
                                    decoration: InputDecoration(
                                      hintText: l10n.tr('add_teams_paste_hint'),
                                      hintStyle: TextStyle(color: onSurface.withOpacity(0.45), fontSize: 12),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                                    label: Text(l10n.tr('add_teams_clear')),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: onSurface.withOpacity(0.80),
                                      side: BorderSide(color: onSurface.withOpacity(0.18)),
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
                                    label: Text(l10n.tr('add_teams_validate')),
                                  ),
                                ),
                              ],
                            ),
                            if (rows.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _MiniChip(
                                    label: '${l10n.tr('add_teams_bulk_ok_prefix')}$okCount',
                                    color: primary.withOpacity(0.18),
                                  ),
                                  const SizedBox(width: 8),
                                  _MiniChip(
                                    label: '${l10n.tr('add_teams_bulk_not_found_prefix')}$notFoundCount',
                                    color: cs.error.withOpacity(0.14),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${_existingTeams.length + _tempTeams.length} / $_maxTeamsForFormat',
                                    style: TextStyle(color: onSurface.withOpacity(0.70), fontSize: 11),
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
                                    final resolvedShort = isOk ? _shareId(r.resolved!.userId) : '';

                                    return Glass(
                                      borderRadius: 16,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor: isOk ? primary.withOpacity(0.18) : onSurface.withOpacity(0.08),
                                              child: Icon(
                                                isOk ? Icons.check : Icons.close,
                                                size: 16,
                                                color: isOk ? primary : onSurface.withOpacity(0.55),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    r.input,
                                                    style: TextStyle(
                                                      color: onSurface,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    isOk
                                                        ? '${r.resolved!.teamName} • $resolvedShort'
                                                        : l10n.tr('add_teams_no_profile_found_short'),
                                                    style: TextStyle(
                                                      color: onSurface.withOpacity(isOk ? 0.72 : 0.45),
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
                                style: TextStyle(
                                  color: cs.error,
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    child: Text(l10n.tr('profile_close_tooltip')),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: validating ? null : () => addValidAndClose(ctx),
                                    icon: const Icon(Icons.playlist_add_check),
                                    label: Text(
                                      rows.isEmpty
                                          ? l10n.tr('add_teams_add_valid')
                                          : '${l10n.tr('add_teams_add_valid')} ($okCount)',
                                    ),
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

  bool _groupStructureValidFor(int totalTeams, List<Team> teams) {
    if (totalTeams != 16 && totalTeams != 32) return false;

    final expectedGroups = totalTeams ~/ 4;
    final allowedGroups = (expectedGroups == 4) ? _groupsAll.take(4).toSet() : _groupsAll.take(8).toSet();

    final counts = <String, int>{};
    for (final t in teams) {
      final gid = (t.groupId ?? '').trim();
      if (gid.isEmpty) return false;
      if (!allowedGroups.contains(gid)) return false;
      counts[gid] = (counts[gid] ?? 0) + 1;
    }

    if (counts.length != expectedGroups) return false;
    for (final c in counts.values) {
      if (c != 4) return false;
    }
    return true;
  }

  /// SAVE button: persists teams only, never generates fixtures.
  Future<void> _saveTeamsOnly({bool silent = false}) async {
    final l10n = context.l10n;
    final now = DateTime.now().millisecondsSinceEpoch;

    final newTeams = _tempTeams.map<Team>((t) {
      final groupName = t['group']!;
      final String? groupId = _isGroupLeague ? groupName : null;

      final userId = t['userId']!;
      final teamName = t['teamName']!;

      return Team(
        id: userId, // internal uid
        leagueId: widget.leagueId,
        name: teamName,
        groupId: groupId,
        updatedAtMs: now,
        version: 1,
      );
    }).toList();

    final allTeams = <Team>[..._existingTeams, ...newTeams];

    await _localRepo.saveTeams(widget.leagueId, allTeams);

    for (final t in newTeams) {
      await _localRepo.assignTeamToUserInLeague(
        leagueId: widget.leagueId,
        userId: t.id,
        teamId: t.id,
      );
    }

    if (!mounted) return;

    setState(() {
      _existingTeams = allTeams;
      _tempTeams.clear();
      _bulkError = null;
    });

    if (!silent) {
      _snackOk(l10n.tr('add_teams_saved_toast'));
      if (!_requiredCountReached) {
        _snackWarn(_unlockHint(l10n));
      }
    }
  }

  /// GENERATE button: generates fixtures ONLY when required team count is reached.
  Future<void> _generateFixturesOnly() async {
    final l10n = context.l10n;

    await _saveTeamsOnly(silent: true);

    final total = _existingTeams.length;

    if (!_requiredCountReached) {
      if (widget.format == LeagueFormat.uclGroup) {
        _snackErr('${l10n.tr('add_teams_cannot_generate_group_prefix')} $total.');
      } else if (widget.format == LeagueFormat.uclSwiss) {
        _snackErr('${l10n.tr('add_teams_cannot_generate_swiss_prefix')} $total.');
      } else {
        _snackErr('${l10n.tr('add_teams_cannot_generate_classic_prefix')} $total.');
      }
      return;
    }

    final existingFixtures = await _localRepo.getMatches(widget.leagueId);

    // Swiss: never allow generating league fixtures if any already exist.
    if (widget.format == LeagueFormat.uclSwiss && existingFixtures.isNotEmpty) {
      _snackErr(l10n.tr('add_teams_swiss_fixtures_already_exist'));
      return;
    }

    // Classic/Group: if fixtures exist, confirm regeneration.
    if (existingFixtures.isNotEmpty && widget.format != LeagueFormat.uclSwiss) {
      final ok = await showDialog<bool>(
            context: context,
            barrierDismissible: true,
            builder: (ctx) {
              final theme = Theme.of(ctx);
              final cs = theme.colorScheme;
              final onSurface = cs.onSurface;

              return AlertDialog(
                backgroundColor: cs.surface,
                title: Text(
                  l10n.tr('add_teams_regenerate_fixtures_title'),
                  style: TextStyle(color: onSurface),
                ),
                content: Text(
                  l10n.tr('add_teams_regenerate_fixtures_message'),
                  style: TextStyle(color: onSurface.withOpacity(0.72)),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(l10n.tr('common_cancel')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(l10n.tr('add_teams_regenerate')),
                  ),
                ],
              );
            },
          ) ??
          false;

      if (!ok) return;
    }

    final doubleRR = _league?.settings.doubleRoundRobin ?? true;
    final swissRounds = _league?.settings.swissRounds ?? 8;

    List<dynamic> generated = [];

    if (widget.format == LeagueFormat.classic) {
      generated = FixtureGenerator.generateClassicLeagueFixtures(
        leagueId: widget.leagueId,
        teams: _existingTeams,
        doubleRoundRobin: doubleRR,
      );
    } else if (widget.format == LeagueFormat.uclGroup) {
      if (!_groupStructureValidFor(total, _existingTeams)) {
        _snackErr(
            '${l10n.tr('add_teams_invalid_group_structure_prefix')} $total ${l10n.tr('add_teams_invalid_group_structure_suffix')}');
        return;
      }

      generated = FixtureGenerator.generateUclGroupStage(
        leagueId: widget.leagueId,
        teams: _existingTeams,
        doubleRoundRobin: doubleRR,
        groupSize: 4,
      );
    } else if (widget.format == LeagueFormat.uclSwiss) {
      generated = SwissPairingEngine.generateInitialRound(
        leagueId: widget.leagueId,
        teams: _existingTeams,
        roundNumber: 1,
        totalRounds: swissRounds,
      );
    }

    if (generated.isEmpty) {
      _snackErr(l10n.tr('add_teams_failed_generate_fixtures'));
      return;
    }

    await _localRepo.replaceMatches(widget.leagueId, generated.cast());
    _snackOk(
        '${l10n.tr('add_teams_fixtures_generated_prefix')}${generated.length}${l10n.tr('add_teams_fixtures_generated_suffix')}');

    if (mounted) {
      context.go('/leagues/${widget.leagueId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;
    final primary = cs.primary;

    final width = MediaQuery.of(context).size.width;
    final showTwoPane = width >= 900;

    final headerGradient = LinearGradient(
      colors: [
        primary.withOpacity(0.95),
        cs.primaryContainer.withOpacity(0.95),
      ],
    );

    return GlassScaffold(
      appBar: AppBar(
        title: Text('${l10n.tr('add_teams_appbar_title_prefix')} · ${_formatLabel(l10n)}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: showTwoPane ? 980 : 620),
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: primary))
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
                                  gradient: headerGradient,
                                ),
                                child: Icon(Icons.sports_soccer, color: cs.onPrimary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.tr('add_teams_header_title'),
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _unlockHint(l10n),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: onSurface.withOpacity(0.70),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_isGroupLeague) ...[
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;
    final primary = cs.primary;

    final existingCount = _existingTeams.length;
    final newCount = _tempTeams.length;
    final totalCount = existingCount + newCount;

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                Icon(Icons.person_add_alt_1, size: 18, color: primary),
                const SizedBox(width: 8),
                Text(
                  l10n.tr('add_teams_add_players_title'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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
                _MiniChip(
                  label: '${l10n.tr('add_teams_saved_prefix')}$existingCount',
                  color: onSurface.withOpacity(0.08),
                ),
                const SizedBox(width: 8),
                _MiniChip(
                  label: '${l10n.tr('add_teams_new_prefix')}$newCount',
                  color: primary.withOpacity(0.18),
                ),
                const Spacer(),
                Text(
                  '$totalCount / $_maxTeamsForFormat',
                  style: TextStyle(color: onSurface.withOpacity(0.70), fontSize: 11),
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
                style: TextStyle(color: cs.error, fontSize: 12, fontWeight: FontWeight.w700),
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
              label: Text(l10n.tr('add_teams_add_one_player')),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showPasteListSheet,
              icon: const Icon(Icons.playlist_add),
              label: Text(l10n.tr('add_teams_paste_list')),
              style: OutlinedButton.styleFrom(
                foregroundColor: onSurface.withOpacity(0.80),
                side: BorderSide(color: onSurface.withOpacity(0.18)),
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _importRosterFromCsv,
              icon: const Icon(Icons.upload_file),
              label: Text(l10n.tr('add_teams_import_csv')),
              style: OutlinedButton.styleFrom(
                foregroundColor: onSurface.withOpacity(0.80),
                side: BorderSide(color: onSurface.withOpacity(0.18)),
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSelector() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;
    final primary = cs.primary;

    final groups = _activeGroups;
    if (groups.isEmpty) return const SizedBox.shrink();

    if (!groups.contains(_selectedGroup)) {
      _selectedGroup = groups.first;
    }

    return Glass(
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.grid_view, size: 18, color: primary),
          const SizedBox(width: 8),
          Text(
            l10n.tr('add_teams_current_group'),
            style: TextStyle(color: onSurface.withOpacity(0.72), fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: groups.map((g) {
                  final label = _groupDisplayName(l10n, g);
                  final selected = _selectedGroup == g;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 11)),
                      selected: selected,
                      selectedColor: primary.withOpacity(0.18),
                      backgroundColor: onSurface.withOpacity(0.06),
                      labelStyle: TextStyle(
                        color: selected ? primary : onSurface.withOpacity(0.72),
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;
    final primary = cs.primary;

    final existingCount = _existingTeams.length;
    final newCount = _tempTeams.length;
    final totalCount = existingCount + newCount;

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                Icon(Icons.groups, size: 18, color: primary),
                const SizedBox(width: 8),
                Text(
                  l10n.tr('add_teams_review_teams'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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
                _MiniChip(
                  label: '${l10n.tr('add_teams_saved_prefix')}$existingCount',
                  color: onSurface.withOpacity(0.08),
                ),
                const SizedBox(width: 8),
                _MiniChip(
                  label: '${l10n.tr('add_teams_new_prefix')}$newCount',
                  color: primary.withOpacity(0.18),
                ),
                const Spacer(),
                Text(
                  '$totalCount / $_maxTeamsForFormat',
                  style: TextStyle(color: onSurface.withOpacity(0.70), fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: (existingCount + newCount) == 0
                ? Center(
                    child: Text(
                      l10n.tr('add_teams_empty_state'),
                      style: TextStyle(
                        color: onSurface.withOpacity(0.55),
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
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
                        final short = _shareId(team.id);
                        final label = _isGroupLeague
                            ? '${l10n.tr('add_teams_label_saved')} · $groupLabel · $short'
                            : '${l10n.tr('add_teams_label_saved')} · $short';

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
                        final short = _shareId(team['userId'] ?? '');
                        final label = group.isEmpty
                            ? '${l10n.tr('add_teams_label_new')} · $short'
                            : '${l10n.tr('add_teams_label_new')} · ${_groupDisplayName(l10n, group)} · $short';

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
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saveTeamsOnly,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    icon: const Icon(Icons.save),
                    label: Text(l10n.tr('add_teams_save_teams')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _requiredCountReached ? _generateFixturesOnly : null,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: primary),
                      foregroundColor: primary,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(l10n.tr('add_teams_generate_fixtures')),
                  ),
                ),
              ],
            ),
          ),
          if (!_requiredCountReached)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _unlockHint(l10n),
                style: TextStyle(
                  color: onSurface.withOpacity(0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _editExistingTeam(int index) {
    final l10n = context.l10n;

    final team = _existingTeams[index];
    String selectedGroup = team.groupId ?? _selectedGroup;

    final activeGroups = _activeGroups;
    if (_isGroupLeague && activeGroups.isNotEmpty && !activeGroups.contains(selectedGroup)) {
      selectedGroup = activeGroups.first;
    }

    final short = _shareId(team.id);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final onSurface = cs.onSurface;
        final primary = cs.primary;

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
                            Text(
                              l10n.tr('add_teams_team_details_title'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                l10n.tr('add_teams_team_name_label'),
                                style: TextStyle(color: onSurface.withOpacity(0.72), fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                team.name,
                                style: TextStyle(color: onSurface, fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                'UserId (short)',
                                style: TextStyle(color: onSurface.withOpacity(0.72), fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                short,
                                style: TextStyle(color: primary, fontWeight: FontWeight.w900),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                '${l10n.tr('add_teams_uid_internal_label')} ${team.id}',
                                style: TextStyle(color: onSurface.withOpacity(0.55), fontSize: 11),
                              ),
                            ),
                            if (_isGroupLeague) ...[
                              const SizedBox(height: 10),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  l10n.tr('add_teams_group_label'),
                                  style: TextStyle(color: onSurface.withOpacity(0.72), fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                              DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: selectedGroup,
                                  dropdownColor: cs.surface,
                                  style: TextStyle(color: primary, fontWeight: FontWeight.w800),
                                  isExpanded: true,
                                  items: _groupsAll
                                      .map(
                                        (g) => DropdownMenuItem(
                                          value: g,
                                          child: Text(_groupDisplayName(l10n, g)),
                                        ),
                                      )
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
                                    child: Text(l10n.tr('profile_close_tooltip')),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: () {
                                      setState(() {
                                        _existingTeams[index] = team.copyWith(
                                          groupId: _isGroupLeague ? selectedGroup : null,
                                          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
                                        );
                                      });
                                      Navigator.of(ctx).pop();
                                    },
                                    child: Text(l10n.tr('add_teams_save_changes')),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _existingTeams.removeAt(index);
                                  });
                                  Navigator.of(ctx).pop();
                                },
                                icon: Icon(Icons.delete, color: cs.error, size: 16),
                                label: Text(l10n.tr('add_teams_remove_team'), style: TextStyle(color: cs.error)),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;
    final primary = cs.primary;

    final numberColor = isNew ? primary : onSurface.withOpacity(0.70);

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
                  backgroundColor: isNew ? primary.withOpacity(0.18) : onSurface.withOpacity(0.08),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(color: numberColor, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onSurface.withOpacity(0.55),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isNew && onTap != null)
                  Icon(
                    Icons.edit,
                    color: onSurface.withOpacity(0.55),
                    size: 16,
                  ),
                if (isNew && onRemove != null)
                  InkWell(
                    onTap: onRemove,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.close, color: onSurface.withOpacity(0.55), size: 16),
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
  final String userId; // Firebase UID
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
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: onSurface,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
