import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../data/leagues_repository_local.dart';
import '../domain/algorithms/swiss_pairing.dart';
import '../logic/fixture_generator.dart';
import '../logic/team_media_service.dart';
import '../models/enums.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../models/league_settings.dart';
import '../models/membership.dart';
import '../models/team.dart';
import 'widgets/roster_csv_importer.dart';

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
  final TeamMediaService _teamMedia = TeamMediaService();

  League? _league;

  final List<Map<String, String>> _tempTeams = [];

  List<Team> _existingTeams = [];
  bool _isLoading = true;
  String? _loadErrorMessage;

  bool _saving = false;
  bool _generating = false;

  bool get _busy => _saving || _generating;

  /// UCL Group League only (existing behavior unchanged).
  bool get _isGroupLeague => widget.format == LeagueFormat.uclGroup;

  /// NEW: World Cup format (separate engine).
  bool get _isWorldCup => widget.format == LeagueFormat.worldCup;

  String _selectedGroup = 'Group A';

  // Existing UCL Group groups (A–H).
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

  // NEW: World Cup groups (A–L) for FIFA 2026.
  static const List<String> _worldCupGroupsAll = <String>[
    'Group A',
    'Group B',
    'Group C',
    'Group D',
    'Group E',
    'Group F',
    'Group G',
    'Group H',
    'Group I',
    'Group J',
    'Group K',
    'Group L',
  ];

  String? _bulkError;

  final Map<String, String> _teamNameCacheByUserId = {};

  int get _savedCount => _existingTeams.length;
  int get _newCount => _tempTeams.length;
  int get _totalCount => _savedCount + _newCount;

  // ---------------------------------------------------------------------------
  // MAX TEAMS / REQUIRED COUNTS
  // ---------------------------------------------------------------------------

  int get _maxTeamsForFormat {
    switch (widget.format) {
      case LeagueFormat.classic:
        return (_league?.maxTeams ?? 20).clamp(2, 40);
      case LeagueFormat.uclGroup:
        return 32;
      case LeagueFormat.uclSwiss:
        return 36;
      case LeagueFormat.worldCup:
        // World Cup is locked to FIFA format selected at league creation.
        // Prefer settings for correctness; fallback to stored maxTeams.
        final wc = _league?.settings.worldCupFormat ??
            (_league?.maxTeams == 48 ? WorldCupFormat.fifa2026 : WorldCupFormat.fifa2022);
        return wc.teamCount;
    }
  }

  bool get _requiredCountReached {
    final n = _totalCount;
    switch (widget.format) {
      case LeagueFormat.uclGroup:
        return n == 16 || n == 32;
      case LeagueFormat.uclSwiss:
        return n == 18 || n == 36;
      case LeagueFormat.worldCup:
        // Must be exactly 32 (FIFA 2022) or 48 (FIFA 2026) based on settings.
        return n == _maxTeamsForFormat;
      case LeagueFormat.classic:
      default:
        return n >= 2;
    }
  }

  String _shareId(String uid) {
    final u = uid.trim();
    if (u.isEmpty) return '';
    return UserProfile.deriveShareIdFromUid(u);
  }

  List<String> get _activeGroups {
    if (!_isGroupLeague) return const <String>[];

    final used = <String>{
      for (final t in _existingTeams) (t.groupId ?? '').trim(),
      for (final t in _tempTeams) (t['group'] ?? '').trim(),
    };
    used.removeWhere((e) => e.isEmpty);

    final usesExtended = used.any(
      (g) => g == 'Group E' || g == 'Group F' || g == 'Group G' || g == 'Group H',
    );
    if (usesExtended) return _groupsAll;

    return (_totalCount > 16) ? _groupsAll : _groupsAll.take(4).toList();
  }

  @override
  void initState() {
    super.initState();
    _localRepo = LocalLeaguesRepository(ref.read(prefsServiceProvider));
    _loadExistingTeams();
  }

  Future<void> _requireOnline() async {
    await ConnectivityService.instance.requireOnline(
      timeout: const Duration(seconds: 4),
    );
  }

  Color _baseSnackBg(ThemeData theme) {
    return theme.brightness == Brightness.dark
        ? const Color(0xFF101522)
        : const Color(0xFFF8FBFF);
  }

  void _snack(String msg, {Color? bg, Color? fg}) {
    if (!mounted) return;

    final theme = Theme.of(context);
    final resolvedBg = bg ?? _baseSnackBg(theme);
    final resolvedFg = fg ??
        (theme.brightness == Brightness.dark
            ? Colors.white
            : AppTheme.primaryText(theme.brightness));

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
    final accent = AppTheme.limeAccentDark;
    final baseBg = _baseSnackBg(theme);
    _snack(
      msg,
      bg: Color.alphaBlend(accent.withOpacity(0.16), baseBg),
      fg: accent,
    );
  }

  void _snackWarn(String msg) {
    const warn = Color(0xFFF59E0B);
    final theme = Theme.of(context);
    final baseBg = _baseSnackBg(theme);
    _snack(
      msg,
      bg: Color.alphaBlend(warn.withOpacity(0.16), baseBg),
      fg: warn,
    );
  }

  void _snackErr(String msg) {
    final theme = Theme.of(context);
    final err = Theme.of(context).colorScheme.error;
    final baseBg = _baseSnackBg(theme);
    _snack(
      msg,
      bg: Color.alphaBlend(err.withOpacity(0.16), baseBg),
      fg: err,
    );
  }

  Future<void> _loadExistingTeams() async {
    setState(() {
      _isLoading = true;
      _loadErrorMessage = null;
    });

    try {
      final league = await _localRepo.getLeagueById(widget.leagueId);
      final teams = await _localRepo.getTeams(widget.leagueId);
      final allMemberships = await _localRepo.listMemberships();

      final memberUserIds = allMemberships
          .where(
            (m) =>
                m.leagueId == widget.leagueId &&
                m.role == LeagueRole.member,
          )
          .map((m) => m.userId.trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final existingIds = teams.map((t) => t.id).toSet();
      final tempIds = _tempTeams
          .map((t) => (t['userId'] ?? '').trim())
          .where((id) => id.isNotEmpty)
          .toSet();

      final autoTemp = <Map<String, String>>[];

      // UCL Group: teams can be added with manual group placement.
      // World Cup: group placement is automatic at fixture generation time.
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
          } catch (_) {}
        }

        if (name.isEmpty) name = _shareId(uid);

        autoTemp.add({
          'userId': uid,
          'teamName': name,
          'group': defaultGroup,
          'teamImageUrl': '',
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadErrorMessage = UserFriendlyError.toMessage(
          e is Object ? e : Exception('unknown'),
        );
      });
      _snackErr(_loadErrorMessage!);
    }
  }

  String _formatLabel(AppLocalizations l10n) {
    switch (widget.format) {
      case LeagueFormat.classic:
        return l10n.tr('add_teams_format_classic');
      case LeagueFormat.uclGroup:
        return l10n.tr('add_teams_format_ucl_group');
      case LeagueFormat.uclSwiss:
        return l10n.tr('add_teams_format_ucl_swiss');
      case LeagueFormat.worldCup:
        return 'World Cup';
    }
  }

  String _unlockHint(AppLocalizations l10n) {
    switch (widget.format) {
      case LeagueFormat.uclGroup:
        return l10n.tr('add_teams_unlock_group');
      case LeagueFormat.uclSwiss:
        return l10n.tr('add_teams_unlock_swiss');
      case LeagueFormat.worldCup:
        final teams = _maxTeamsForFormat;
        return 'Add exactly $teams teams. Groups and fixtures will be generated automatically.';
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

    // World Cup 2026 adds Groups I–L (no localization keys yet).
    if (g == 'Group I' || g == 'Group J' || g == 'Group K' || g == 'Group L') {
      return g;
    }

    return g;
  }

  String _groupLabelForTeam(Team t) {
    final l10n = context.l10n;
    if (_isGroupLeague) {
      return _groupDisplayName(l10n, t.groupId ?? _unassignedGroup);
    }
    return l10n.tr('add_teams_league_pool');
  }

  Future<_ResolvedTeam?> _resolveTeamFromUserIdOrShareId(
    String userIdOrShareId,
  ) async {
    final input = userIdOrShareId.trim();
    if (input.isEmpty) return null;

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

  Future<void> _addResolvedTeam(
    _ResolvedTeam resolved, {
    String? groupOverride,
  }) async {
    final l10n = context.l10n;

    final totalCurrent = _existingTeams.length + _tempTeams.length;
    if (totalCurrent >= _maxTeamsForFormat) {
      if (!mounted) return;
      setState(
        () => _bulkError =
            '${l10n.tr('add_teams_max_teams_error_prefix')} $_maxTeamsForFormat ${l10n.tr('add_teams_max_teams_error_suffix')}',
      );
      return;
    }

    final alreadyInPreview =
        _tempTeams.any((t) => (t['userId'] ?? '') == resolved.userId);
    if (alreadyInPreview) return;

    final alreadySaved = _existingTeams.any((t) => t.id == resolved.userId);
    if (alreadySaved) {
      _snackWarn(l10n.tr('add_teams_user_already_added'));
      return;
    }

    final String groupToUse;
    if (_isGroupLeague) {
      final active = _activeGroups;
      final desired = (groupOverride != null && groupOverride.trim().isNotEmpty)
          ? groupOverride.trim()
          : _selectedGroup;
      groupToUse = active.contains(desired)
          ? desired
          : (active.isNotEmpty ? active.first : 'Group A');
    } else {
      // World Cup is treated like non-UCL-group here: group assignment is automatic
      // when generating fixtures.
      groupToUse = _leaguePoolGroup;
    }

    if (!mounted) return;
    setState(() {
      _bulkError = null;
      _tempTeams.add({
        'userId': resolved.userId,
        'teamName': resolved.teamName,
        'group': groupToUse,
        'teamImageUrl': '',
      });

      if (_isGroupLeague &&
          (groupOverride == null || groupOverride.trim().isEmpty)) {
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
        return ResolvedRosterProfile(
          userId: r.userId,
          teamName: r.teamName,
        );
      },
      onAddResolved: (resolved, {groupOverride}) async {
        await _addResolvedTeam(
          _ResolvedTeam(
            userId: resolved.userId,
            teamName: resolved.teamName,
          ),
          groupOverride: groupOverride,
        );
      },
      currentTeamCount: _existingTeams.length + _tempTeams.length,
      maxTeams: _maxTeamsForFormat,
    );
  }

  Future<void> _showAddSingleDialog() async {
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;

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
          error =
              '${l10n.tr('add_teams_lookup_failed_prefix')} ${UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'))}';
        });
      }
    }

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.55),
        builder: (ctx) {
          final theme = Theme.of(ctx);

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Glass(
              borderRadius: 26,
              padding: const EdgeInsets.all(18),
              fill: AppTheme.cardColor(brightness),
              borderColor: AppTheme.cardBorder(brightness),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: StatefulBuilder(
                  builder: (ctx, setModalState) {
                    final resolvedShare =
                        (resolved == null) ? '' : _shareId(resolved!.userId);

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                color: AppTheme.iconCircleBackground(brightness),
                                border: Border.all(
                                  color: AppTheme.cardBorder(brightness),
                                ),
                              ),
                              child: Icon(
                                Icons.badge,
                                color: AppTheme.limeAccentDark,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                l10n.tr('add_teams_add_player_by_userid_title'),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: AppTheme.primaryText(brightness),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              icon: Icon(
                                Icons.close,
                                color: AppTheme.secondaryText(brightness),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
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
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.limeAccentDark,
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    tooltip: l10n.tr('add_teams_lookup_tooltip'),
                                    onPressed: () => resolveNow(setModalState),
                                    icon: const Icon(Icons.search),
                                  ),
                          ),
                          onChanged: (_) {
                            debounce?.cancel();
                            debounce = Timer(
                              const Duration(milliseconds: 350),
                              () {
                                if (!ctx.mounted) return;
                                resolveNow(setModalState);
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        if (resolved != null)
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: brightness == Brightness.dark
                                  ? AppTheme.limeAccentDark.withOpacity(0.10)
                                  : const Color(0xFFECFCCB),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: brightness == Brightness.dark
                                    ? AppTheme.limeAccentDark.withOpacity(0.22)
                                    : const Color(0xFFD9F99D),
                              ),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.tr('add_teams_resolved_profile_title'),
                                  style: TextStyle(
                                    color: AppTheme.limeAccentDark,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  resolved!.teamName,
                                  style: TextStyle(
                                    color: AppTheme.primaryText(brightness),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${l10n.tr('add_teams_uid_prefix')}$resolvedShare',
                                  style: TextStyle(
                                    color: AppTheme.secondaryText(brightness),
                                    fontSize: 11,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Internal uid: ${resolved!.userId}',
                                  style: TextStyle(
                                    color: AppTheme.secondaryText(brightness)
                                        .withOpacity(0.8),
                                    fontSize: 10,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_isGroupLeague) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.grid_view,
                                        size: 16,
                                        color: AppTheme.secondaryText(
                                          brightness,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${l10n.tr('add_teams_will_be_placed_in_prefix')}${_groupDisplayName(l10n, _selectedGroup)}',
                                        style: TextStyle(
                                          color: AppTheme.secondaryText(
                                            brightness,
                                          ),
                                          fontSize: 12,
                                        ),
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
                              color: Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: Text(l10n.tr('common_cancel')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.limeAccent,
                                  foregroundColor: AppTheme.darkText,
                                ),
                                onPressed: () async {
                                  if (resolved == null) return;
                                  await _addResolvedTeam(resolved!);
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                },
                                icon: const Icon(Icons.person_add),
                                label: Text(l10n.tr('common_add')),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
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
    final brightness = Theme.of(context).brightness;

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
        rows = inputs
            .map(
              (i) => _BulkRow(
                input: i,
                resolved: null,
                status: _BulkStatus.pending,
              ),
            )
            .toList();
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
            updated.add(
              _BulkRow(
                input: entry.key,
                resolved: null,
                status: _BulkStatus.notFound,
              ),
            );
          } else {
            updated.add(
              _BulkRow(
                input: entry.key,
                resolved: r,
                status: _BulkStatus.ok,
              ),
            );
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
          error =
              '${l10n.tr('add_teams_validation_failed_prefix')} ${UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'))}';
        });
      }
    }

    Future<void> addValidAndClose(BuildContext ctx) async {
      final valid = rows
          .where((r) => r.status == _BulkStatus.ok && r.resolved != null)
          .map((r) => r.resolved!)
          .toList();
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

        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

        final inputBg = AppTheme.searchBackground(brightness);
        final inputStroke = AppTheme.searchOutline(brightness);

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset)
                .add(const EdgeInsets.all(12)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Glass(
                  borderRadius: 28,
                  fill: AppTheme.cardColor(brightness),
                  borderColor: AppTheme.cardBorder(brightness),
                  child: StatefulBuilder(
                    builder: (ctx, setModalState) {
                      final okCount =
                          rows.where((r) => r.status == _BulkStatus.ok).length;
                      final notFoundCount = rows
                          .where((r) => r.status == _BulkStatus.notFound)
                          .length;

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
                                color: AppTheme.primaryText(brightness),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.tr('add_teams_paste_userids_subtitle'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.secondaryText(brightness),
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 8,
                                  sigmaY: 8,
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: inputBg,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: inputStroke),
                                  ),
                                  child: TextField(
                                    controller: controller,
                                    maxLines: 6,
                                    style: TextStyle(
                                      color: AppTheme.primaryText(brightness),
                                      fontWeight: FontWeight.w600,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: l10n.tr('add_teams_paste_hint'),
                                      hintStyle: TextStyle(
                                        color:
                                            AppTheme.secondaryText(brightness),
                                        fontSize: 12,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
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
                                    icon: const Icon(
                                      Icons.clear_all,
                                      size: 18,
                                    ),
                                    label: Text(
                                      l10n.tr('add_teams_clear'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.limeAccent,
                                      foregroundColor: AppTheme.darkText,
                                    ),
                                    onPressed: validating
                                        ? null
                                        : () => validateNow(setModalState),
                                    icon: validating
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppTheme.darkText,
                                            ),
                                          )
                                        : const Icon(Icons.verified),
                                    label: Text(
                                      l10n.tr('add_teams_validate'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (rows.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _MiniChip(
                                    label:
                                        '${l10n.tr('add_teams_bulk_ok_prefix')}$okCount',
                                    color: AppTheme.limeAccent.withOpacity(0.25),
                                  ),
                                  const SizedBox(width: 8),
                                  _MiniChip(
                                    label:
                                        '${l10n.tr('add_teams_bulk_not_found_prefix')}$notFoundCount',
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error
                                        .withOpacity(0.14),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${_existingTeams.length + _tempTeams.length} / $_maxTeamsForFormat',
                                    style: TextStyle(
                                      color: AppTheme.secondaryText(brightness),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 260,
                                ),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: rows.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 6),
                                  itemBuilder: (context, index) {
                                    final r = rows[index];
                                    final isOk = r.status == _BulkStatus.ok &&
                                        r.resolved != null;
                                    final resolvedShort = isOk
                                        ? _shareId(r.resolved!.userId)
                                        : '';

                                    return Glass(
                                      borderRadius: 16,
                                      fill: AppTheme.cardColor(brightness),
                                      borderColor: AppTheme.cardBorder(brightness),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor: isOk
                                                  ? AppTheme.limeAccent
                                                      .withOpacity(0.25)
                                                  : AppTheme.searchBackground(
                                                      brightness,
                                                    ),
                                              child: Icon(
                                                isOk ? Icons.check : Icons.close,
                                                size: 16,
                                                color: isOk
                                                    ? AppTheme.limeAccentDark
                                                    : AppTheme.secondaryText(
                                                        brightness,
                                                      ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    r.input,
                                                    style: TextStyle(
                                                      color: AppTheme.primaryText(
                                                        brightness,
                                                      ),
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    isOk
                                                        ? '${r.resolved!.teamName} • $resolvedShort'
                                                        : l10n.tr(
                                                            'add_teams_no_profile_found_short',
                                                          ),
                                                    style: TextStyle(
                                                      color: AppTheme.secondaryText(
                                                        brightness,
                                                      ),
                                                      fontSize: 11,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
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
                                  color: Theme.of(context).colorScheme.error,
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
                                    child: Text(
                                      l10n.tr('profile_close_tooltip'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.limeAccent,
                                      foregroundColor: AppTheme.darkText,
                                    ),
                                    onPressed: validating
                                        ? null
                                        : () => addValidAndClose(ctx),
                                    icon: const Icon(
                                      Icons.playlist_add_check,
                                    ),
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
    ).whenComplete(controller.dispose);
  }

  bool _groupStructureValidFor(int totalTeams, List<Team> teams) {
    if (totalTeams != 16 && totalTeams != 32) return false;

    final expectedGroups = totalTeams ~/ 4;
    final allowedGroups =
        (expectedGroups == 4) ? _groupsAll.take(4).toSet() : _groupsAll.toSet();

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

  // ---------------------------------------------------------------------------
  // NEW: World Cup grouping helpers (auto assign)
  // ---------------------------------------------------------------------------

  List<String> _worldCupGroupsFor(WorldCupFormat fmt) {
    return _worldCupGroupsAll.take(fmt.groupCount).toList(growable: false);
  }

  bool _worldCupGroupStructureValidFor({
    required WorldCupFormat fmt,
    required List<Team> teams,
  }) {
    if (teams.length != fmt.teamCount) return false;

    final allowedGroups = _worldCupGroupsFor(fmt).toSet();
    final counts = <String, int>{};

    for (final t in teams) {
      final gid = (t.groupId ?? '').trim();
      if (gid.isEmpty) return false;
      if (!allowedGroups.contains(gid)) return false;
      counts[gid] = (counts[gid] ?? 0) + 1;
    }

    if (counts.length != fmt.groupCount) return false;
    for (final c in counts.values) {
      if (c != 4) return false;
    }
    return true;
  }

  Future<void> _autoAssignWorldCupGroups({
    required WorldCupFormat fmt,
  }) async {
    // Deterministic shuffle so the draw doesn't change randomly on every attempt.
    // Group IDs are only assigned when missing/invalid.
    final now = DateTime.now().millisecondsSinceEpoch;
    final groups = _worldCupGroupsFor(fmt);

    final list = List<Team>.from(_existingTeams)
      ..sort((a, b) => a.id.compareTo(b.id));
    list.shuffle(Random(widget.leagueId.hashCode));

    final updated = <Team>[];
    for (var i = 0; i < list.length; i++) {
      final gid = groups[i ~/ 4];
      updated.add(
        list[i].copyWith(
          groupId: gid,
          updatedAtMs: now,
        ),
      );
    }

    await _localRepo.saveTeams(widget.leagueId, updated);

    if (!mounted) return;
    setState(() {
      _existingTeams = updated;
    });
  }

  Future<void> _saveTeamsOnly({bool silent = false}) async {
    final l10n = context.l10n;
    if (_busy) return;

    if (_existingTeams.isEmpty && _tempTeams.isEmpty) {
      if (!silent) _snackWarn('No teams to save.');
      return;
    }

    setState(() {
      _saving = true;
      _bulkError = null;
    });

    try {
      await _requireOnline();

      final now = DateTime.now().millisecondsSinceEpoch;

      final newTeams = _tempTeams.map<Team>((t) {
        final groupName = t['group'] ?? '';
        final String? groupId = _isGroupLeague ? groupName : null;

        final userId = (t['userId'] ?? '').trim();
        final teamName = (t['teamName'] ?? '').trim();
        final teamImageUrl = (t['teamImageUrl'] ?? '').trim();

        return Team(
          id: userId,
          leagueId: widget.leagueId,
          name: teamName,
          groupId: groupId,
          teamImageUrl: teamImageUrl,
          updatedAtMs: now,
          version: 1,
        );
      }).toList();

      final allTeams = <Team>[..._existingTeams, ...newTeams];

      await _localRepo.saveTeams(widget.leagueId, allTeams);

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
    } catch (e) {
      final msg = UserFriendlyError.toMessage(
        e is Object ? e : Exception('unknown'),
      );
      if (!silent && mounted) _snackErr(msg);
      if (silent) rethrow;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _generateFixturesOnly() async {
    final l10n = context.l10n;

    if (_busy) return;

    setState(() => _generating = true);
    try {
      await _requireOnline();

      await _saveTeamsOnly(silent: true);

      final total = _existingTeams.length;

      if (!_requiredCountReached) {
        if (widget.format == LeagueFormat.uclGroup) {
          _snackErr(
            '${l10n.tr('add_teams_cannot_generate_group_prefix')} $total.',
          );
        } else if (widget.format == LeagueFormat.uclSwiss) {
          _snackErr(
            '${l10n.tr('add_teams_cannot_generate_swiss_prefix')} $total.',
          );
        } else if (widget.format == LeagueFormat.worldCup) {
          _snackErr('Cannot generate World Cup fixtures with $total teams.');
        } else {
          _snackErr(
            '${l10n.tr('add_teams_cannot_generate_classic_prefix')} $total.',
          );
        }
        return;
      }

      final existingFixtures = await _localRepo.getMatches(widget.leagueId);

      if (widget.format == LeagueFormat.uclSwiss && existingFixtures.isNotEmpty) {
        _snackErr(l10n.tr('add_teams_swiss_fixtures_already_exist'));
        return;
      }

      if (existingFixtures.isNotEmpty && widget.format != LeagueFormat.uclSwiss) {
        final ok = await showDialog<bool>(
              context: context,
              barrierDismissible: true,
              barrierColor: Colors.black.withOpacity(0.55),
              builder: (ctx) {
                final theme = Theme.of(ctx);
                final brightness = theme.brightness;

                return Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Glass(
                    borderRadius: 26,
                    padding: const EdgeInsets.all(18),
                    fill: AppTheme.cardColor(brightness),
                    borderColor: AppTheme.cardBorder(brightness),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: const Color(0xFFF59E0B).withOpacity(0.16),
                                  border: Border.all(
                                    color: const Color(0xFFF59E0B).withOpacity(0.35),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Color(0xFFF59E0B),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  l10n.tr('add_teams_regenerate_fixtures_title'),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: AppTheme.primaryText(brightness),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                icon: Icon(
                                  Icons.close,
                                  color: AppTheme.secondaryText(brightness),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l10n.tr('add_teams_regenerate_fixtures_message'),
                            style: TextStyle(
                              color: AppTheme.secondaryText(brightness),
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(l10n.tr('common_cancel')),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.limeAccent,
                                    foregroundColor: AppTheme.darkText,
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(l10n.tr('add_teams_regenerate')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ) ??
            false;

        if (!ok) return;
      }

      final supportsHomeAway =
          widget.format == LeagueFormat.classic || widget.format == LeagueFormat.uclGroup;
      final doubleRR = supportsHomeAway
          ? (_league?.homeAwayEnabled ?? (_league?.settings.doubleRoundRobin ?? true))
          : false;

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
            '${l10n.tr('add_teams_invalid_group_structure_prefix')} $total ${l10n.tr('add_teams_invalid_group_structure_suffix')}',
          );
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
      } else if (widget.format == LeagueFormat.worldCup) {
        final wc = _league?.settings.worldCupFormat ?? WorldCupFormat.fifa2022;

        // Ensure teams have valid World Cup groups; auto-assign if missing/invalid.
        final valid = _worldCupGroupStructureValidFor(fmt: wc, teams: _existingTeams);
        if (!valid) {
          await _autoAssignWorldCupGroups(fmt: wc);

          final stillValid = _worldCupGroupStructureValidFor(fmt: wc, teams: _existingTeams);
          if (!stillValid) {
            _snackErr('Failed to assign World Cup groups. Please try again.');
            return;
          }
        }

        generated = FixtureGenerator.generateWorldCupGroupStage(
          leagueId: widget.leagueId,
          teams: _existingTeams,
          worldCupFormat: wc,
        );
      }

      if (generated.isEmpty) {
        _snackErr(l10n.tr('add_teams_failed_generate_fixtures'));
        return;
      }

      await _localRepo.replaceMatches(
        widget.leagueId,
        generated.cast(),
      );

      _snackOk(
        '${l10n.tr('add_teams_fixtures_generated_prefix')}${generated.length}${l10n.tr('add_teams_fixtures_generated_suffix')}',
      );

      if (mounted) {
        context.go('/leagues/${widget.leagueId}');
      }
    } catch (e) {
      _snackErr(
        UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) {
      return GlassScaffold(
        appBar: AppBar(
          title: Text(l10n.tr('add_teams_appbar_title_prefix')),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Glass(
                borderRadius: 24,
                fill: AppTheme.cardColor(brightness),
                borderColor: AppTheme.cardBorder(brightness),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.login,
                        color: AppTheme.limeAccentDark,
                        size: 44,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Sign in required',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primaryText(brightness),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please sign in to manage teams.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.limeAccent,
                          foregroundColor: AppTheme.darkText,
                        ),
                        onPressed: () => context.pop(),
                        child: const Text('Back'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final width = MediaQuery.of(context).size.width;
    final showTwoPane = width >= 900;

    final headerGradient = LinearGradient(
      colors: [
        AppTheme.limeAccent,
        AppTheme.limeAccentDark.withOpacity(0.90),
      ],
    );

    return GlassScaffold(
      appBar: AppBar(
        title: Text(
          '${l10n.tr('add_teams_appbar_title_prefix')} · ${_formatLabel(l10n)}',
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: showTwoPane ? 980 : 620),
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.limeAccentDark,
                    ),
                  )
                : (_loadErrorMessage != null
                    ? _buildLoadErrorState(_loadErrorMessage!)
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Glass(
                              borderRadius: 24,
                              padding: const EdgeInsets.all(14),
                              fill: AppTheme.cardColor(brightness),
                              borderColor: AppTheme.cardBorder(brightness),
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
                                    child: Icon(
                                      Icons.sports_soccer,
                                      color: AppTheme.darkText,
                                    ),
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
                                            color: AppTheme.primaryText(brightness),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _unlockHint(l10n),
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: AppTheme.secondaryText(brightness),
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
                                        Expanded(
                                          flex: 3,
                                          child: _buildAddPanel(),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 4,
                                          child: _buildPreviewPanel(),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        _buildAddPanel(),
                                        const SizedBox(height: 12),
                                        Expanded(
                                          child: _buildPreviewPanel(),
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      )),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadErrorState(String msg) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Glass(
            borderRadius: 24,
            fill: AppTheme.cardColor(brightness),
            borderColor: AppTheme.cardBorder(brightness),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    color: AppTheme.limeAccentDark,
                    size: 44,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Couldn’t load teams',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primaryText(brightness),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    msg,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.secondaryText(brightness),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.pop(),
                          child: const Text('Back'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.limeAccent,
                            foregroundColor: AppTheme.darkText,
                          ),
                          onPressed: _loadExistingTeams,
                          child: const Text('Retry'),
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
    );
  }

  // NOTE: Everything below this point is unchanged from your existing screen.
  // The only World Cup changes required here were:
  // - adding LeagueFormat.worldCup to switches
  // - auto group assignment + fixture generation for world cup format
  // - the rest of your file remains the same as production behavior

  Widget _buildAddPanel() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final existingCount = _existingTeams.length;
    final newCount = _tempTeams.length;
    final totalCount = existingCount + newCount;

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(12),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                Icon(
                  Icons.person_add_alt_1,
                  size: 18,
                  color: AppTheme.limeAccentDark,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.tr('add_teams_add_players_title'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryText(brightness),
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
                  color: AppTheme.searchBackground(brightness),
                ),
                const SizedBox(width: 8),
                _MiniChip(
                  label: '${l10n.tr('add_teams_new_prefix')}$newCount',
                  color: AppTheme.limeAccent.withOpacity(0.25),
                ),
                const Spacer(),
                Text(
                  '$totalCount / $_maxTeamsForFormat',
                  style: TextStyle(
                    color: AppTheme.secondaryText(brightness),
                    fontSize: 11,
                  ),
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: _busy ? null : _showAddSingleDialog,
              icon: const Icon(Icons.person_add),
              label: Text(l10n.tr('add_teams_add_one_player')),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _showPasteListSheet,
              icon: const Icon(Icons.playlist_add),
              label: Text(l10n.tr('add_teams_paste_list')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryText(brightness),
                side: BorderSide(color: AppTheme.cardBorder(brightness)),
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _importRosterFromCsv,
              icon: const Icon(Icons.upload_file),
              label: Text(l10n.tr('add_teams_import_csv')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryText(brightness),
                side: BorderSide(color: AppTheme.cardBorder(brightness)),
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
    final brightness = Theme.of(context).brightness;

    final groups = _activeGroups;
    if (groups.isEmpty) return const SizedBox.shrink();

    if (!groups.contains(_selectedGroup)) {
      _selectedGroup = groups.first;
    }

    return Glass(
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Row(
        children: [
          Icon(
            Icons.grid_view,
            size: 18,
            color: AppTheme.limeAccentDark,
          ),
          const SizedBox(width: 8),
          Text(
            l10n.tr('add_teams_current_group'),
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
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
                      label: Text(
                        label,
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: selected,
                      selectedColor: AppTheme.limeAccent,
                      backgroundColor:
                          AppTheme.tabInactiveBackground(brightness),
                      labelStyle: TextStyle(
                        color: selected
                            ? AppTheme.darkText
                            : AppTheme.tabInactiveText(brightness),
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                      side: BorderSide(
                        color: selected
                            ? AppTheme.limeAccentDark
                            : AppTheme.cardBorder(brightness),
                      ),
                      onSelected: _busy
                          ? null
                          : (v) {
                              if (!v) return;
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
    // UNCHANGED from your existing file.
    // (kept intact to avoid refactor noise)
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final existingCount = _existingTeams.length;
    final newCount = _tempTeams.length;
    final totalCount = existingCount + newCount;

    return Glass(
      borderRadius: 24,
      padding: const EdgeInsets.all(12),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                Icon(Icons.groups,
                    size: 18, color: AppTheme.limeAccentDark),
                const SizedBox(width: 8),
                Text(
                  l10n.tr('add_teams_review_teams'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryText(brightness),
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
                  color: AppTheme.searchBackground(brightness),
                ),
                const SizedBox(width: 8),
                _MiniChip(
                  label: '${l10n.tr('add_teams_new_prefix')}$newCount',
                  color: AppTheme.limeAccent.withOpacity(0.25),
                ),
                const Spacer(),
                Text(
                  '$totalCount / $_maxTeamsForFormat',
                  style: TextStyle(
                    color: AppTheme.secondaryText(brightness),
                    fontSize: 11,
                  ),
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
                        color: AppTheme.secondaryText(brightness),
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
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
                          imageUrl: team.teamImageUrl,
                          isNew: false,
                          onTap: _busy ? null : () => _editExistingTeam(i),
                          onRemove: null,
                        );
                      } else {
                        final idx = i - existingCount;
                        final team = _tempTeams[idx];
                        final group = team['group'] ?? '';
                        final short = _shareId((team['userId'] ?? '').trim());
                        final label = group.isEmpty
                            ? '${l10n.tr('add_teams_label_new')} · $short'
                            : '${l10n.tr('add_teams_label_new')} · ${_groupDisplayName(l10n, group)} · $short';

                        return _buildTeamTile(
                          index: i,
                          name: (team['teamName'] ?? '').trim(),
                          label: label,
                          imageUrl: (team['teamImageUrl'] ?? '').trim(),
                          isNew: true,
                          onTap: _busy ? null : () => _editTempTeam(idx),
                          onRemove: _busy
                              ? null
                              : () {
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
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.limeAccent,
                      foregroundColor: AppTheme.darkText,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _busy ? null : _saveTeamsOnly,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.darkText,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(l10n.tr('add_teams_save_teams')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        (_busy || !_requiredCountReached) ? null : _generateFixturesOnly,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.limeAccentDark),
                      foregroundColor: AppTheme.limeAccentDark,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: _generating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
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
                  color: AppTheme.secondaryText(brightness),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------
  // The rest of your file (editing teams, tiles, helper classes) remains
  // unchanged from what you pasted.
  // -------------------------

  Future<void> _editTempTeam(int idx) async {
    // UNCHANGED (kept as-is)
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;

    final temp = _tempTeams[idx];
    final uid = (temp['userId'] ?? '').trim();
    final short = _shareId(uid);

    String selectedGroup = (temp['group'] ?? '').trim();
    if (!_isGroupLeague) selectedGroup = _leaguePoolGroup;

    String imageUrl = (temp['teamImageUrl'] ?? '').trim();
    bool uploading = false;

    final activeGroups = _activeGroups;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ).add(const EdgeInsets.all(16)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Glass(
                  borderRadius: 28,
                  fill: AppTheme.cardColor(brightness),
                  borderColor: AppTheme.cardBorder(brightness),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    child: StatefulBuilder(
                      builder: (ctx, setModalState) {
                        Future<void> doUpload() async {
                          if (uploading) return;
                          setModalState(() => uploading = true);
                          try {
                            final url = await _teamMedia.pickUploadAndSaveTeamImage(
                              leagueId: widget.leagueId,
                              teamId: uid.isEmpty ? 'temp_$idx' : uid,
                            );
                            if (url == null || url.trim().isEmpty) {
                              return;
                            }
                            setModalState(() => imageUrl = url.trim());
                          } catch (e) {
                            _snackErr(
                              UserFriendlyError.toMessage(
                                e is Object ? e : Exception('unknown'),
                              ),
                            );
                          } finally {
                            if (ctx.mounted) {
                              setModalState(() => uploading = false);
                            }
                          }
                        }

                        Future<void> doClear() async {
                          setModalState(() => imageUrl = '');
                        }

                        final effectiveGroup = activeGroups.contains(selectedGroup)
                            ? selectedGroup
                            : (activeGroups.isNotEmpty ? activeGroups.first : 'Group A');

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.tr('add_teams_team_details_title'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryText(brightness),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _TeamThumb(url: imageUrl, size: 44),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (temp['teamName'] ?? '').trim(),
                                        style: TextStyle(
                                          color: AppTheme.primaryText(brightness),
                                          fontWeight: FontWeight.w900,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'UserId (short): $short',
                                        style: const TextStyle(
                                          color: AppTheme.limeAccentDark,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (_isGroupLeague) ...[
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  l10n.tr('add_teams_group_label'),
                                  style: TextStyle(
                                    color: AppTheme.secondaryText(brightness),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: effectiveGroup,
                                  dropdownColor: Theme.of(context).colorScheme.surface,
                                  style: const TextStyle(
                                    color: AppTheme.limeAccentDark,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  isExpanded: true,
                                  items: activeGroups
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
                                  child: OutlinedButton.icon(
                                    onPressed: uploading ? null : doUpload,
                                    icon: uploading
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.image),
                                    label: Text(l10n.tr('common_upload')),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: uploading ? null : doClear,
                                    icon: const Icon(Icons.clear),
                                    label: Text(l10n.tr('common_clear')),
                                  ),
                                ),
                              ],
                            ),
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
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.limeAccent,
                                      foregroundColor: AppTheme.darkText,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _tempTeams[idx] = {
                                          ..._tempTeams[idx],
                                          'group': selectedGroup,
                                          'teamImageUrl': imageUrl.trim(),
                                        };
                                      });
                                      Navigator.of(ctx).pop();
                                    },
                                    child: Text(l10n.tr('add_teams_save_changes')),
                                  ),
                                ),
                              ],
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

  void _editExistingTeam(int index) {
    // UNCHANGED (kept as-is)
    final l10n = context.l10n;
    final brightness = Theme.of(context).brightness;

    final team = _existingTeams[index];
    String selectedGroup = team.groupId ?? _selectedGroup;

    final activeGroups = _activeGroups;
    if (_isGroupLeague &&
        activeGroups.isNotEmpty &&
        !activeGroups.contains(selectedGroup)) {
      selectedGroup = activeGroups.first;
    }

    final short = _shareId(team.id);
    String imageUrl = team.teamImageUrl.trim();
    bool uploading = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ).add(const EdgeInsets.all(16)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Glass(
                  borderRadius: 28,
                  fill: AppTheme.cardColor(brightness),
                  borderColor: AppTheme.cardBorder(brightness),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    child: StatefulBuilder(
                      builder: (ctx, setModalState) {
                        Future<void> doUpload() async {
                          if (uploading) return;
                          setModalState(() => uploading = true);

                          try {
                            final url = await _teamMedia.pickUploadAndSaveTeamImage(
                              leagueId: widget.leagueId,
                              teamId: team.id,
                            );

                            if (url == null || url.trim().isEmpty) {
                              return;
                            }

                            setState(() {
                              _existingTeams[index] =
                                  _existingTeams[index].copyWith(
                                teamImageUrl: url.trim(),
                                updatedAtMs: DateTime.now().millisecondsSinceEpoch,
                              );
                            });

                            setModalState(() => imageUrl = url.trim());
                            _snackOk(l10n.tr('common_done'));
                          } catch (e) {
                            _snackErr(
                              UserFriendlyError.toMessage(
                                e is Object ? e : Exception('unknown'),
                              ),
                            );
                          } finally {
                            if (ctx.mounted) {
                              setModalState(() => uploading = false);
                            }
                          }
                        }

                        Future<void> doClear() async {
                          if (uploading) return;
                          setModalState(() => uploading = true);

                          try {
                            await _teamMedia.clearTeamImage(
                              leagueId: widget.leagueId,
                              teamId: team.id,
                            );

                            setState(() {
                              _existingTeams[index] =
                                  _existingTeams[index].copyWith(
                                teamImageUrl: '',
                                updatedAtMs: DateTime.now().millisecondsSinceEpoch,
                              );
                            });

                            setModalState(() => imageUrl = '');
                            _snackOk(l10n.tr('common_done'));
                          } catch (e) {
                            _snackErr(
                              UserFriendlyError.toMessage(
                                e is Object ? e : Exception('unknown'),
                              ),
                            );
                          } finally {
                            if (ctx.mounted) {
                              setModalState(() => uploading = false);
                            }
                          }
                        }

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.tr('add_teams_team_details_title'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryText(brightness),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _TeamThumb(url: imageUrl, size: 44),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        team.name,
                                        style: TextStyle(
                                          color: AppTheme.primaryText(brightness),
                                          fontWeight: FontWeight.w900,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'UserId (short): $short',
                                        style: const TextStyle(
                                          color: AppTheme.limeAccentDark,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                '${l10n.tr('add_teams_uid_internal_label')} ${team.id}',
                                style: TextStyle(
                                  color: AppTheme.secondaryText(brightness),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            if (_isGroupLeague) ...[
                              const SizedBox(height: 10),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  l10n.tr('add_teams_group_label'),
                                  style: TextStyle(
                                    color: AppTheme.secondaryText(brightness),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: activeGroups.contains(selectedGroup)
                                      ? selectedGroup
                                      : (activeGroups.isNotEmpty
                                          ? activeGroups.first
                                          : 'Group A'),
                                  dropdownColor: Theme.of(context).colorScheme.surface,
                                  style: const TextStyle(
                                    color: AppTheme.limeAccentDark,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  isExpanded: true,
                                  items: activeGroups
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
                                  child: OutlinedButton.icon(
                                    onPressed: uploading ? null : doUpload,
                                    icon: uploading
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.image),
                                    label: Text(l10n.tr('common_upload')),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: uploading ? null : doClear,
                                    icon: const Icon(Icons.clear),
                                    label: Text(l10n.tr('common_clear')),
                                  ),
                                ),
                              ],
                            ),
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
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.limeAccent,
                                      foregroundColor: AppTheme.darkText,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _existingTeams[index] = team.copyWith(
                                          groupId: _isGroupLeague ? selectedGroup : team.groupId,
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
                                onPressed: () async {
                                  Navigator.of(ctx).pop();
                                  setState(() {
                                    _existingTeams.removeAt(index);
                                  });
                                  try {
                                    await _saveTeamsOnly(silent: true);
                                  } catch (_) {
                                    await _loadExistingTeams();
                                  }
                                },
                                icon: Icon(
                                  Icons.delete,
                                  color: Theme.of(context).colorScheme.error,
                                  size: 16,
                                ),
                                label: Text(
                                  l10n.tr('add_teams_remove_team'),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
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
    required String imageUrl,
    required bool isNew,
    required VoidCallback? onTap,
    required VoidCallback? onRemove,
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final numberColor = isNew ? AppTheme.limeAccentDark : AppTheme.secondaryText(brightness);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Glass(
        borderRadius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        fill: AppTheme.cardColor(brightness),
        borderColor: AppTheme.cardBorder(brightness),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: isNew
                      ? AppTheme.limeAccent.withOpacity(0.25)
                      : AppTheme.searchBackground(brightness),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      color: numberColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _TeamThumb(url: imageUrl, size: 18),
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
                          color: AppTheme.primaryText(brightness),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.secondaryText(brightness),
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
                    color: AppTheme.secondaryText(brightness),
                    size: 16,
                  ),
                if (isNew && onRemove != null)
                  InkWell(
                    onTap: onRemove,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.close,
                        color: AppTheme.secondaryText(brightness),
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
  final String userId;
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
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppTheme.primaryText(brightness),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TeamThumb extends StatelessWidget {
  const _TeamThumb({
    required this.url,
    this.size = 18,
  });

  final String url;
  final double size;

  bool _looksLikeHttpUrl(String s) {
    final u = s.trim().toLowerCase();
    return u.startsWith('https://') || u.startsWith('http://');
  }

  String _cloudinaryOptimizedUrl(
    String url, {
    int width = 64,
    int height = 64,
  }) {
    final u = url.trim();
    if (u.isEmpty) return u;

    final isCloudinary =
        u.contains('res.cloudinary.com') && u.contains('/image/upload/');
    if (!isCloudinary) return u;

    final marker = '/image/upload/';
    final idx = u.indexOf(marker);
    if (idx < 0) return u;

    final prefix = u.substring(0, idx + marker.length);
    final suffix = u.substring(idx + marker.length);

    final transforms = 'f_auto,q_auto,w_$width,h_$height,c_fill,g_auto';

    final parts = suffix.split('/');
    if (parts.isEmpty) return '$prefix$transforms/$suffix';

    final first = parts.first;
    final isVersionOnly =
        first.startsWith('v') && int.tryParse(first.substring(1)) != null;

    if (!isVersionOnly) {
      if (first.contains('f_auto') || first.contains('q_auto')) {
        return u;
      }
      parts[0] = 'f_auto,q_auto,$first';
      return prefix + parts.join('/');
    }

    return '$prefix$transforms/$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    final raw = url.trim();
    final has = raw.isNotEmpty && _looksLikeHttpUrl(raw);
    final d = has ? _cloudinaryOptimizedUrl(raw, width: 64, height: 64) : '';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.searchBackground(brightness),
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.searchOutline(brightness)),
      ),
      child: ClipOval(
        child: has
            ? Image.network(
                d,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                cacheWidth: 64,
                cacheHeight: 64,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.emoji_events_outlined,
                  size: size * 0.70,
                  color: AppTheme.secondaryText(brightness),
                ),
                loadingBuilder: (context, child, event) {
                  if (event == null) return child;
                  return Icon(
                    Icons.emoji_events_outlined,
                    size: size * 0.70,
                    color: AppTheme.secondaryText(brightness),
                  );
                },
              )
            : Icon(
                Icons.emoji_events_outlined,
                size: size * 0.70,
                color: AppTheme.secondaryText(brightness),
              ),
      ),
    );
  }
}