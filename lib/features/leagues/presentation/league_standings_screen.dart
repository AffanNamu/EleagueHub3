// lib/features/leagues/presentation/league_standings_screen.dart
//
// MODIFIED: Added World Cup standings display.
//
// Changes:
// - Added case for LeagueFormat.worldCup in the format switch.
// - World Cup shows per-group standings tables (same pattern as uclGroup).
// - Added group name resolver for World Cup groups A–L (12 groups).
// - Added World Cup qualification legend showing:
//     Green  → Qualified (top 2 per group)
//     Amber  → Best 3rd (FIFA 2026 only: 8 best 3rd-placed teams)
//     Red    → Eliminated
// - All existing cases (classic, uclGroup, uclSwiss) are completely unchanged.
// - _displayGroupName extended to handle Group I through Group L.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../domain/standings/standings.dart';
import '../models/league_format.dart';
import '../models/league_settings.dart';
import 'standings_providers.dart';
import 'widgets/standings_table.dart';

class LeagueStandingsScreen extends ConsumerStatefulWidget {
  final String id;

  const LeagueStandingsScreen({
    super.key,
    required this.id,
  });

  @override
  ConsumerState<LeagueStandingsScreen> createState() =>
      _LeagueStandingsScreenState();
}

class _LeagueStandingsScreenState
    extends ConsumerState<LeagueStandingsScreen> {
  bool _refreshing = false;

  Map<String, String> _teamImageUrls = {};
  final Set<String> _requestedUserImageIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: discarded_futures
      _refresh();
    });
    unawaited(_loadTeamImagesBestEffort());
  }

  // ── Group name resolver — extended for World Cup groups A–L ───────────────

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
      // World Cup 2026 additional groups (I through L).
      case 'Group I':
        return 'Group I';
      case 'Group J':
        return 'Group J';
      case 'Group K':
        return 'Group K';
      case 'Group L':
        return 'Group L';
      default:
        return groupId;
    }
  }

  bool _looksLikeFirebaseUid(String s) => s.trim().length > 20;

  String _bestEffortUrlFromMap(Map<String, dynamic> data) {
    const keys = <String>[
      'teamImageUrl',
      'imageUrl',
      'logoUrl',
      'photoUrl',
      'profileImageUrl',
      'avatarUrl',
    ];
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  String _bestUserImageUrlFromUserDoc(Map<String, dynamic> data) {
    final teamImageUrl = (data['teamImageUrl'] as String?)?.trim() ?? '';
    if (teamImageUrl.isNotEmpty) return teamImageUrl;

    final profileImageUrl =
        (data['profileImageUrl'] as String?)?.trim() ?? '';
    if (profileImageUrl.isNotEmpty) return profileImageUrl;

    final photoUrl = (data['photoUrl'] as String?)?.trim() ?? '';
    if (photoUrl.isNotEmpty) return photoUrl;

    return '';
  }

  Future<Map<String, String>> _fetchUserImagesByIds(List<String> ids) async {
    final clean = ids
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && _looksLikeFirebaseUid(e))
        .toList(growable: false);
    if (clean.isEmpty) return const <String, String>{};

    final out = <String, String>{};

    const chunkSize = 10;
    for (var i = 0; i < clean.length; i += chunkSize) {
      final chunk = clean.sublist(
        i,
        (i + chunkSize > clean.length) ? clean.length : i + chunkSize,
      );

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));

      for (final d in snap.docs) {
        final url = _bestUserImageUrlFromUserDoc(d.data());
        if (url.trim().isNotEmpty) out[d.id] = url.trim();
      }
    }

    return out;
  }

  Future<void> _loadTeamImagesBestEffort() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('leagues')
          .doc(widget.id)
          .collection('teams')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));

      final out = <String, String>{};
      final teamIds = <String>[];

      for (final d in snap.docs) {
        final data = d.data();
        final id =
            (data['id'] is String && (data['id'] as String).trim().isNotEmpty)
                ? (data['id'] as String).trim()
                : d.id;
        teamIds.add(id);

        final url = _bestEffortUrlFromMap(data);
        if (id.trim().isNotEmpty && url.isNotEmpty) out[id] = url;
      }

      final userImages = await _fetchUserImagesByIds(teamIds);
      for (final e in userImages.entries) {
        out[e.key] = e.value;
      }

      if (!mounted) return;
      if (out.isEmpty) return;

      setState(() => _teamImageUrls = {..._teamImageUrls, ...out});
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<void> _ensureUserImagesForTeamIds(List<String> ids) async {
    final missing = <String>[];
    for (final id in ids) {
      final clean = id.trim();
      if (!_looksLikeFirebaseUid(clean)) continue;
      if (_requestedUserImageIds.contains(clean)) continue;
      if ((_teamImageUrls[clean] ?? '').trim().isNotEmpty) {
        _requestedUserImageIds.add(clean);
        continue;
      }
      missing.add(clean);
      _requestedUserImageIds.add(clean);
    }

    if (missing.isEmpty) return;

    try {
      final userImages = await _fetchUserImagesByIds(missing);
      if (!mounted) return;
      if (userImages.isEmpty) return;

      setState(() => _teamImageUrls = {..._teamImageUrls, ...userImages});
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);

    ref.invalidate(leagueProvider(widget.id));
    ref.invalidate(leagueStandingsProvider(widget.id));
    ref.invalidate(leagueGroupedStandingsProvider(widget.id));

    unawaited(_loadTeamImagesBestEffort());

    if (mounted) setState(() => _refreshing = false);
  }

  Widget _errorText(
      BuildContext context, String prefixKey, Object error) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final message = UserFriendlyError.toMessage(error);

    return Center(
      child: Text(
        '${l10n.tr(prefixKey)}\n$message',
        style: TextStyle(
          color: cs.onSurface.withOpacity(0.72),
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _rowTeamId(StandingsRow row) {
    try {
      final dyn = row as dynamic;
      final v = (dyn.teamId as String?) ?? '';
      if (v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    try {
      final dyn = row as dynamic;
      final v = (dyn.id as String?) ?? '';
      if (v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return '';
  }

  String _rowTeamName(StandingsRow row) {
    try {
      final dyn = row as dynamic;
      final v = (dyn.teamName as String?) ?? '';
      if (v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    try {
      final dyn = row as dynamic;
      final v = (dyn.name as String?) ?? '';
      if (v.trim().isNotEmpty) return v.trim();
    } catch (_) {}
    return '';
  }

  Widget _avatarStrip(List<StandingsRow> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final take =
        rows.length > 12 ? rows.take(12).toList() : rows.toList();
    final ids = <String>[];
    final names = <String>[];

    for (final r in take) {
      ids.add(_rowTeamId(r));
      names.add(_rowTeamName(r));
    }

    if (ids.every((e) => e.trim().isEmpty)) return const SizedBox.shrink();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: discarded_futures
      _ensureUserImagesForTeamIds(ids);
    });

    final chipFill = theme.brightness == Brightness.light
        ? Colors.white.withOpacity(0.34)
        : cs.onSurface.withOpacity(0.04);
    final chipBorder = theme.brightness == Brightness.light
        ? Colors.white.withOpacity(0.70)
        : cs.onSurface.withOpacity(0.10);

    return Container(
      height: 28,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ids.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final id = ids[i].trim();
          final name = names[i].trim();
          final url =
              (id.isEmpty ? '' : (_teamImageUrls[id] ?? '')).trim();

          final bool idLooksUid = _looksLikeFirebaseUid(id);
          final displayLabel =
              name.isNotEmpty ? name : (idLooksUid ? 'TEAM' : id);
          final tooltipLabel =
              name.isNotEmpty ? name : (idLooksUid ? 'Team' : id);

          return Tooltip(
            message: tooltipLabel,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: chipFill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: chipBorder),
                boxShadow: theme.brightness == Brightness.light
                    ? <BoxShadow>[
                        BoxShadow(
                          color:
                              const Color(0xFFB4D2FF).withOpacity(0.14),
                          blurRadius: 18,
                          offset: const Offset(0, 12),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TeamThumb(url: url),
                  const SizedBox(width: 6),
                  Text(
                    displayLabel.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface.withOpacity(0.70),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final leagueAsync = ref.watch(leagueProvider(widget.id));

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.tr('standings_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: l10n.tr('admin_knockout_reload_tooltip'),
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: cs.primary),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: cs.primary,
          backgroundColor: theme.brightness == Brightness.light
              ? Colors.white.withOpacity(0.92)
              : cs.surface,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Glass(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(
                          l10n.tr('standings_section_title')),
                      const SizedBox(height: 12),
                      Expanded(
                        child: leagueAsync.when(
                          loading: () => Center(
                            child: CircularProgressIndicator(
                                color: cs.primary),
                          ),
                          error: (error, _) => _errorText(
                            context,
                            'standings_failed_load_league_prefix',
                            error,
                          ),
                          data: (league) {
                            switch (league.format) {
                              // ── UCL Group (UNCHANGED) ──────────────────
                              case LeagueFormat.uclGroup:
                                return _buildGroupedStandings(
                                  context: context,
                                  expectedGroupCounts: const [4, 8],
                                  showQualificationLegend: false,
                                  worldCupFormat: null,
                                );

                              // ── World Cup (NEW) ────────────────────────
                              case LeagueFormat.worldCup:
                                return _buildGroupedStandings(
                                  context: context,
                                  // 8 groups (FIFA 2022) or 12 groups (FIFA 2026).
                                  expectedGroupCounts: const [8, 12],
                                  showQualificationLegend: true,
                                  worldCupFormat:
                                      league.settings.worldCupFormat,
                                );

                              // ── UCL Swiss (UNCHANGED) ──────────────────
                              case LeagueFormat.uclSwiss:
                                return _buildSwissStandings(
                                    context, league.settings);

                              // ── Classic (UNCHANGED) ────────────────────
                              case LeagueFormat.classic:
                              default:
                                return _buildClassicStandings(
                                    context);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── NEW: Grouped standings builder (shared by uclGroup + worldCup) ─────────

  Widget _buildGroupedStandings({
    required BuildContext context,
    required List<int> expectedGroupCounts,
    required bool showQualificationLegend,
    required WorldCupFormat? worldCupFormat,
  }) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final groupedAsync =
        ref.watch(leagueGroupedStandingsProvider(widget.id));

    return groupedAsync.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: cs.primary)),
      error: (error, _) => _errorText(
        context,
        'standings_failed_load_group_standings_prefix',
        error,
      ),
      data: (groupMap) {
        if (groupMap.isEmpty) {
          return Center(
            child: Text(
              l10n.tr('standings_no_group_results_yet'),
              style: TextStyle(
                color: cs.onSurface.withOpacity(0.55),
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          );
        }

        final groupKeys = groupMap.keys.toList()..sort();
        final invalidGroupCount =
            !expectedGroupCounts.contains(groupKeys.length);
        final invalidGroupSizes =
            groupKeys.any((g) => (groupMap[g]?.length ?? 0) != 4);

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: groupKeys.length +
              ((invalidGroupCount || invalidGroupSizes) ? 1 : 0) +
              (showQualificationLegend ? 1 : 0),
          itemBuilder: (context, index) {
            // Warning banner at top if structure is invalid.
            if ((invalidGroupCount || invalidGroupSizes) &&
                index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${l10n.tr('standings_ucl_group_structure_warning_prefix')}'
                  '${groupKeys.length}'
                  '${l10n.tr('standings_ucl_group_structure_warning_suffix')}',
                  style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
              );
            }

            // World Cup qualification legend at bottom.
            final legendIndex = groupKeys.length +
                ((invalidGroupCount || invalidGroupSizes) ? 1 : 0);
            if (showQualificationLegend && index == legendIndex) {
              return _buildWorldCupQualificationLegend(
                worldCupFormat: worldCupFormat,
              );
            }

            final adjIndex =
                (invalidGroupCount || invalidGroupSizes)
                    ? index - 1
                    : index;

            final groupId = groupKeys[adjIndex];
            final rows = groupMap[groupId] ?? const <StandingsRow>[];

            // Color builder for World Cup qualification zones.
            Color Function(BuildContext, int, StandingsRow, int)?
                rowColorBuilder;
            if (showQualificationLegend) {
              rowColorBuilder = _worldCupRowColorBuilder(
                worldCupFormat: worldCupFormat,
                groupCount: groupKeys.length,
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: adjIndex == groupKeys.length - 1 ? 0 : 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // World Cup group header with globe icon.
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        if (showQualificationLegend) ...[
                          const Icon(
                            Icons.public_rounded,
                            size: 14,
                            color: Color(0xFFD97706),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          _displayGroupName(groupId),
                          style: TextStyle(
                            color: showQualificationLegend
                                ? const Color(0xFFD97706)
                                : cs.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _avatarStrip(rows),
                  StandingsTable(
                    rows: rows,
                    rowColorBuilder: rowColorBuilder,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── NEW: World Cup qualification color builder ─────────────────────────────

  /// Returns a row color builder function that colors rows by qualification zone.
  ///
  /// FIFA 2022 (8 groups): top 2 qualify (green), 3rd and 4th eliminated.
  /// FIFA 2026 (12 groups): top 2 qualify (green), best 8 third-placed
  ///   may qualify (amber — only deterministic after all group matches),
  ///   4th eliminated.
  Color Function(BuildContext, int, StandingsRow, int)
      _worldCupRowColorBuilder({
    required WorldCupFormat? worldCupFormat,
    required int groupCount,
  }) {
    // FIFA 2022 colors.
    final qualifiedColor =
        const Color(0xFF22C55E).withOpacity(0.12); // Green — qualified top 2.
    final potentialThirdColor =
        const Color(0xFFF59E0B).withOpacity(0.10); // Amber — potential best 3rd.
    final eliminatedColor =
        Colors.red.withOpacity(0.07); // Red — eliminated.

    return (ctx, index, row, totalRows) {
      final rank = index + 1; // 1-based rank within group.

      if (rank <= 2) {
        // Top 2: always qualify.
        return qualifiedColor;
      }

      if (rank == 3) {
        // 3rd placed: may qualify in FIFA 2026 (best 8 of 12 thirds).
        // In FIFA 2022, 3rd-placed teams do not advance.
        if (worldCupFormat == WorldCupFormat.fifa2026 &&
            groupCount == 12) {
          return potentialThirdColor;
        }
        return eliminatedColor;
      }

      // 4th placed: always eliminated.
      return eliminatedColor;
    };
  }

  // ── NEW: World Cup qualification legend widget ─────────────────────────────

  Widget _buildWorldCupQualificationLegend({
    required WorldCupFormat? worldCupFormat,
  }) {
    final cs = Theme.of(context).colorScheme;
    final is2026 = worldCupFormat == WorldCupFormat.fifa2026;

    Widget dot(Color c) => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(
              color: cs.onSurface.withOpacity(0.18),
              width: 0.5,
            ),
          ),
        );

    final labelStyle = TextStyle(
      color: cs.onSurface.withOpacity(0.55),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              dot(const Color(0xFF22C55E).withOpacity(0.55)),
              const SizedBox(width: 6),
              Text('Qualified (Top 2)', style: labelStyle),
            ],
          ),
          if (is2026)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                dot(const Color(0xFFF59E0B).withOpacity(0.55)),
                const SizedBox(width: 6),
                Text('Potential Best 3rd (8 of 12)', style: labelStyle),
              ],
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              dot(Colors.red.withOpacity(0.45)),
              const SizedBox(width: 6),
              Text('Eliminated', style: labelStyle),
            ],
          ),
        ],
      ),
    );
  }

  // ── Existing: Swiss standings builder (UNCHANGED) ─────────────────────────

  Widget _buildSwissStandings(
      BuildContext context, dynamic settings) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final standingsAsync =
        ref.watch(leagueStandingsProvider(widget.id));

    return standingsAsync.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: cs.primary)),
      error: (error, _) => _errorText(
        context,
        'standings_failed_load_standings_prefix',
        error,
      ),
      data: (rows) {
        return FutureBuilder<int>(
          future: _getSwissCurrentRound(ref, widget.id),
          builder: (context, snapshot) {
            final current = snapshot.data ?? 0;

            // Safe access to swissRounds regardless of settings type.
            int swissRounds = 8;
            try {
              if (settings is LeagueSettings) {
                swissRounds = settings.swissRounds;
              }
            } catch (_) {}

            final label = current == 0
                ? '${l10n.tr('standings_swiss_phase_no_rounds_yet_prefix')}$swissRounds${l10n.tr('standings_swiss_phase_no_rounds_yet_suffix')}'
                : '${l10n.tr('standings_swiss_phase_round_prefix')}$current${l10n.tr('standings_swiss_phase_round_mid')}$swissRounds';

            final autoColor =
                const Color(0xFF22C55E).withOpacity(0.12);
            final playoffColor = cs.primary.withOpacity(0.10);
            final eliminatedColor = cs.error.withOpacity(0.08);

            final n = rows.length;
            final allowed = (n == 18 || n == 36);

            final int autoCut =
                (n == 36) ? 8 : (n == 18 ? 4 : 0);
            final int playoffCut =
                (n == 36) ? 24 : (n == 18 ? 12 : 0);

            if (rows.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: cs.onSurface.withOpacity(0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Center(
                      child: Text(
                        l10n.tr('standings_no_results_yet'),
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.55),
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.55),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (!allowed) ...[
                  Text(
                    '${l10n.tr('standings_swiss_team_count_warning_prefix')}$n.',
                    style: const TextStyle(
                      color: Color(0xFFF59E0B),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  _swissLegendDynamic(
                    context: context,
                    teamCount: n,
                    autoColor: autoColor,
                    playoffColor: playoffColor,
                    eliminatedColor: eliminatedColor,
                  ),
                  const SizedBox(height: 8),
                ],
                _avatarStrip(rows),
                Expanded(
                  child: StandingsTable(
                    rows: rows,
                    allowSorting: false,
                    rowColorBuilder: (ctx, index, row, totalRows) {
                      if (!allowed) return Colors.transparent;
                      final rank = index + 1;
                      if (rank <= autoCut) return autoColor;
                      if (rank <= playoffCut) return playoffColor;
                      return eliminatedColor;
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── Existing: Classic standings builder (UNCHANGED) ───────────────────────

  Widget _buildClassicStandings(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final standingsAsync =
        ref.watch(leagueStandingsProvider(widget.id));

    return standingsAsync.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: cs.primary)),
      error: (error, _) => _errorText(
        context,
        'standings_failed_load_standings_prefix',
        error,
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Center(
            child: Text(
              l10n.tr('standings_no_results_yet'),
              style: TextStyle(
                color: cs.onSurface.withOpacity(0.55),
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _avatarStrip(rows),
            Expanded(child: StandingsTable(rows: rows)),
          ],
        );
      },
    );
  }
}

// ── Existing: Swiss round helper (UNCHANGED) ──────────────────────────────────

Future<int> _getSwissCurrentRound(WidgetRef ref, String leagueId) async {
  try {
    final repo = ref.read(localLeaguesRepositoryProvider);
    final allMatches = await repo.getMatches(leagueId);
    if (allMatches.isEmpty) return 0;
    return allMatches
        .map((m) => m.roundNumber)
        .reduce((a, b) => a > b ? a : b);
  } catch (_) {
    return 0;
  }
}

// ── Existing: Swiss legend (UNCHANGED) ────────────────────────────────────────

Widget _swissLegendDynamic({
  required BuildContext context,
  required int teamCount,
  required Color autoColor,
  required Color playoffColor,
  required Color eliminatedColor,
}) {
  final l10n = context.l10n;
  final cs = Theme.of(context).colorScheme;

  Widget dot(Color c) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
              color: cs.onSurface.withOpacity(0.18), width: 0.5),
        ),
      );

  final labelStyle = TextStyle(
    color: cs.onSurface.withOpacity(0.55),
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );

  if (teamCount == 36) {
    return Row(
      children: [
        dot(autoColor),
        const SizedBox(width: 6),
        Text(l10n.tr('standings_swiss_legend_top8_r16'),
            style: labelStyle),
        const SizedBox(width: 12),
        dot(playoffColor),
        const SizedBox(width: 6),
        Text(l10n.tr('standings_swiss_legend_9_24_playoff'),
            style: labelStyle),
        const SizedBox(width: 12),
        dot(eliminatedColor),
        const SizedBox(width: 6),
        Text(l10n.tr('standings_swiss_legend_25_36_eliminated'),
            style: labelStyle),
      ],
    );
  }

  return Row(
    children: [
      dot(autoColor),
      const SizedBox(width: 6),
      Text(l10n.tr('standings_swiss_legend_top4_quarter_finals'),
          style: labelStyle),
      const SizedBox(width: 12),
      dot(playoffColor),
      const SizedBox(width: 6),
      Text(l10n.tr('standings_swiss_legend_5_12_playoff'),
          style: labelStyle),
      const SizedBox(width: 12),
      dot(eliminatedColor),
      const SizedBox(width: 6),
      Text(l10n.tr('standings_swiss_legend_13_18_eliminated'),
          style: labelStyle),
    ],
  );
}

// ── Existing: _TeamThumb (UNCHANGED) ──────────────────────────────────────────

class _TeamThumb extends StatelessWidget {
  const _TeamThumb({required this.url});

  final String url;

  bool _looksLikeHttpUrl(String s) {
    final u = s.trim().toLowerCase();
    return u.startsWith('https://') || u.startsWith('http://');
  }

  String _cloudinaryOptimizedUrl(String url,
      {int width = 64, int height = 64}) {
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
      if (first.contains('f_auto') || first.contains('q_auto')) return u;
      parts[0] = 'f_auto,q_auto,$first';
      return prefix + parts.join('/');
    }

    return '$prefix$transforms/$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final raw = url.trim();
    final has = raw.isNotEmpty && _looksLikeHttpUrl(raw);
    final d = has ? _cloudinaryOptimizedUrl(raw, width: 64, height: 64) : '';

    final fill = theme.brightness == Brightness.light
        ? Colors.white.withOpacity(0.40)
        : cs.onSurface.withOpacity(0.06);
    final border = theme.brightness == Brightness.light
        ? Colors.white.withOpacity(0.72)
        : cs.onSurface.withOpacity(0.14);

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: border),
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
                  size: 12,
                  color: cs.onSurface.withOpacity(0.55),
                ),
                loadingBuilder: (context, child, event) {
                  if (event == null) return child;
                  return Icon(
                    Icons.emoji_events_outlined,
                    size: 12,
                    color: cs.onSurface.withOpacity(0.55),
                  );
                },
              )
            : Icon(
                Icons.emoji_events_outlined,
                size: 12,
                color: cs.onSurface.withOpacity(0.55),
              ),
      ),
    );
  }
}