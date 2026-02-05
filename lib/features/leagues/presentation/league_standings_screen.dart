import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/services/sync_trigger.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/widgets/section_header.dart';
import '../domain/standings/standings.dart';
import '../models/league_format.dart';
import 'standings_providers.dart';
import 'widgets/standings_table.dart';

class LeagueStandingsScreen extends ConsumerStatefulWidget {
  final String id;

  const LeagueStandingsScreen({
    super.key,
    required this.id,
  });

  @override
  ConsumerState<LeagueStandingsScreen> createState() => _LeagueStandingsScreenState();
}

class _LeagueStandingsScreenState extends ConsumerState<LeagueStandingsScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _syncAndRefresh();
    });
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

  Future<void> _syncAndRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);

    await SyncTrigger.trySync();

    ref.invalidate(leagueProvider(widget.id));
    ref.invalidate(leagueStandingsProvider(widget.id));
    ref.invalidate(leagueGroupedStandingsProvider(widget.id));

    if (mounted) setState(() => _refreshing = false);
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
            onPressed: _refreshing ? null : _syncAndRefresh,
            icon: _refreshing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _syncAndRefresh,
          color: cs.primary,
          backgroundColor: cs.surface,
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
                      SectionHeader(l10n.tr('standings_section_title')),
                      const SizedBox(height: 12),
                      Expanded(
                        child: leagueAsync.when(
                          loading: () => Center(
                            child: CircularProgressIndicator(color: cs.primary),
                          ),
                          error: (error, stack) => Center(
                            child: Text(
                              '${l10n.tr('standings_failed_load_league_prefix')}\n${error.toString()}',
                              style: TextStyle(color: cs.onSurface.withOpacity(0.72), fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          data: (league) {
                            switch (league.format) {
                              case LeagueFormat.uclGroup:
                                final groupedAsync = ref.watch(leagueGroupedStandingsProvider(widget.id));
                                return groupedAsync.when(
                                  loading: () => Center(
                                    child: CircularProgressIndicator(color: cs.primary),
                                  ),
                                  error: (error, stack) => Center(
                                    child: Text(
                                      '${l10n.tr('standings_failed_load_group_standings_prefix')}\n${error.toString()}',
                                      style: TextStyle(color: cs.onSurface.withOpacity(0.72), fontWeight: FontWeight.w600),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  data: (groupMap) {
                                    if (groupMap.isEmpty) {
                                      return Center(
                                        child: Text(
                                          l10n.tr('standings_no_group_results_yet'),
                                          style: TextStyle(color: cs.onSurface.withOpacity(0.55), fontWeight: FontWeight.w600),
                                          textAlign: TextAlign.center,
                                        ),
                                      );
                                    }

                                    final groupKeys = groupMap.keys.toList()..sort();

                                    final invalidGroupCount = !(groupKeys.length == 4 || groupKeys.length == 8);
                                    final invalidGroupSizes = groupKeys.any((g) => (groupMap[g]?.length ?? 0) != 4);

                                    return ListView.builder(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      itemCount: groupKeys.length + ((invalidGroupCount || invalidGroupSizes) ? 1 : 0),
                                      itemBuilder: (context, index) {
                                        // Warning header if invalid counts/sizes
                                        if ((invalidGroupCount || invalidGroupSizes) && index == 0) {
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 12),
                                            child: Text(
                                              '${l10n.tr('standings_ucl_group_structure_warning_prefix')}${groupKeys.length}${l10n.tr('standings_ucl_group_structure_warning_suffix')}',
                                              style: const TextStyle(
                                                color: Color(0xFFF59E0B),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          );
                                        }

                                        final adjIndex = (invalidGroupCount || invalidGroupSizes) ? index - 1 : index;

                                        final groupId = groupKeys[adjIndex];
                                        final rows = groupMap[groupId] ?? const <StandingsRow>[];

                                        return Padding(
                                          padding: EdgeInsets.only(
                                            bottom: adjIndex == groupKeys.length - 1 ? 0 : 16,
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                                child: Text(
                                                  _displayGroupName(groupId),
                                                  style: TextStyle(
                                                    color: cs.primary,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              StandingsTable(rows: rows),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );

                              case LeagueFormat.uclSwiss:
                                final standingsAsync = ref.watch(leagueStandingsProvider(widget.id));
                                return standingsAsync.when(
                                  loading: () => Center(
                                    child: CircularProgressIndicator(color: cs.primary),
                                  ),
                                  error: (error, stack) => Center(
                                    child: Text(
                                      '${l10n.tr('standings_failed_load_standings_prefix')}\n${error.toString()}',
                                      style: TextStyle(color: cs.onSurface.withOpacity(0.72), fontWeight: FontWeight.w600),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  data: (rows) {
                                    return FutureBuilder<int>(
                                      future: _getSwissCurrentRound(ref, widget.id),
                                      builder: (context, snapshot) {
                                        final current = snapshot.data ?? 0;
                                        final total = league.settings.swissRounds;

                                        final label = current == 0
                                            ? '${l10n.tr('standings_swiss_phase_no_rounds_yet_prefix')}$total${l10n.tr('standings_swiss_phase_no_rounds_yet_suffix')}'
                                            : '${l10n.tr('standings_swiss_phase_round_prefix')}$current${l10n.tr('standings_swiss_phase_round_mid')}$total';

                                        final autoColor = const Color(0xFF22C55E).withOpacity(0.12);
                                        final playoffColor = cs.primary.withOpacity(0.10);
                                        final eliminatedColor = cs.error.withOpacity(0.08);

                                        final n = rows.length;
                                        final allowed = (n == 18 || n == 36);

                                        // Define zones based on allowed team count.
                                        final int autoCut = (n == 36) ? 8 : (n == 18 ? 4 : 0);
                                        final int playoffCut = (n == 36) ? 24 : (n == 18 ? 12 : 0);

                                        if (rows.isEmpty) {
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              Text(
                                                label,
                                                style: TextStyle(color: cs.onSurface.withOpacity(0.55), fontSize: 12, fontWeight: FontWeight.w600),
                                              ),
                                              const SizedBox(height: 12),
                                              Expanded(
                                                child: Center(
                                                  child: Text(
                                                    l10n.tr('standings_no_results_yet'),
                                                    style: TextStyle(color: cs.onSurface.withOpacity(0.55), fontWeight: FontWeight.w600),
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
                                              style: TextStyle(color: cs.onSurface.withOpacity(0.55), fontSize: 12, fontWeight: FontWeight.w600),
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
                                            Expanded(
                                              child: StandingsTable(
                                                rows: rows,
                                                // Keep qualification coloring consistent with the ranking order
                                                // returned by the standings provider.
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

                              case LeagueFormat.classic:
                              default:
                                final standingsAsync = ref.watch(leagueStandingsProvider(widget.id));
                                return standingsAsync.when(
                                  loading: () => Center(
                                    child: CircularProgressIndicator(color: cs.primary),
                                  ),
                                  error: (error, stack) => Center(
                                    child: Text(
                                      '${l10n.tr('standings_failed_load_standings_prefix')}\n${error.toString()}',
                                      style: TextStyle(color: cs.onSurface.withOpacity(0.72), fontWeight: FontWeight.w600),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  data: (rows) {
                                    if (rows.isEmpty) {
                                      return Center(
                                        child: Text(
                                          l10n.tr('standings_no_results_yet'),
                                          style: TextStyle(color: cs.onSurface.withOpacity(0.55), fontWeight: FontWeight.w600),
                                          textAlign: TextAlign.center,
                                        ),
                                      );
                                    }
                                    return StandingsTable(rows: rows);
                                  },
                                );
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
}

Future<int> _getSwissCurrentRound(WidgetRef ref, String leagueId) async {
  final repo = ref.read(localLeaguesRepositoryProvider);
  final allMatches = await repo.getMatches(leagueId);
  if (allMatches.isEmpty) return 0;
  return allMatches.map((m) => m.roundNumber).reduce((a, b) => a > b ? a : b);
}

Widget _swissLegendDynamic({
  required BuildContext context,
  required int teamCount,
  required Color autoColor,
  required Color playoffColor,
  required Color eliminatedColor,
}) {
  final l10n = context.l10n;
  final theme = Theme.of(context);
  final cs = theme.colorScheme;

  Widget dot(Color c) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: cs.onSurface.withOpacity(0.18), width: 0.5),
        ),
      );

  final labelStyle = TextStyle(color: cs.onSurface.withOpacity(0.55), fontSize: 11, fontWeight: FontWeight.w600);

  if (teamCount == 36) {
    return Row(
      children: [
        dot(autoColor),
        const SizedBox(width: 6),
        Text(l10n.tr('standings_swiss_legend_top8_r16'), style: labelStyle),
        const SizedBox(width: 12),
        dot(playoffColor),
        const SizedBox(width: 6),
        Text(l10n.tr('standings_swiss_legend_9_24_playoff'), style: labelStyle),
        const SizedBox(width: 12),
        dot(eliminatedColor),
        const SizedBox(width: 6),
        Text(l10n.tr('standings_swiss_legend_25_36_eliminated'), style: labelStyle),
      ],
    );
  }

  // teamCount == 18
  return Row(
    children: [
      dot(autoColor),
      const SizedBox(width: 6),
      Text(l10n.tr('standings_swiss_legend_top4_quarter_finals'), style: labelStyle),
      const SizedBox(width: 12),
      dot(playoffColor),
      const SizedBox(width: 6),
      Text(l10n.tr('standings_swiss_legend_5_12_playoff'), style: labelStyle),
      const SizedBox(width: 12),
      dot(eliminatedColor),
      const SizedBox(width: 6),
      Text(l10n.tr('standings_swiss_legend_13_18_eliminated'), style: labelStyle),
    ],
  );
}
